# ris TODO

Rules: SPEC.md. Goal: no GC or general heap, including the runtime.
Measure: test/ris/heap_budget.txt, semantic gates and binary link audits.

How to work (fewer tokens, faster to the goal):

* Demand first: take the largest heap site in an existing workload.
  For an uncovered language guarantee, add a small representative gate.
* One change, one relevant gate: check the promised behavior, including
  error paths the census cannot see. Zero counted allocations alone do
  not prove runtime exemptions or repeated use are heap-free.
* Replace, don't wrap: when a String API has a tape twin, grep the repo
  for callers. Few: move them and delete the String API in one commit.
* TODO holds open work only, one item per task; completed work lives in
  git log. Remove an item when its guarantee passes its gate.
* Linux x86_64 and aarch64 only (SPEC 7.1): no work for other targets.

## Now: every scope frees (SPEC 1.1, 1.5, 1.9, 3.2, 3.5, 3.6; 2026-10-31)

Today a def's, loop's or block's scratch is freed only when
TapeScopeChecker#safe? proves nothing escapes; otherwise the mark stays
off and the scratch stays until the enclosing scope ends. Measured
(1,000,000 rounds in one `tape do`):

* `t = a.first * 100` in the loop body (`first` is not in READS, so the
  body reads outer tape): 2.1 GB RSS. The same in a def: 266 MB. A def
  that frees: 7.6 MB.
* A def's fresh result is staged by `__iyi_scope_result` and copied back
  twice: `def f(p); File.read(p); end` on a 21 MB file is 41 ms and
  16,232 page faults, `File.read(p)` called directly 15 ms and 5,540.
  Same for `a + "x"`, interpolation, `String.new(a)`,
  `Array(UInt8).new(n) { }`, `def f; g; end`. A local grown in place
  (`w = ""; w << x; w`) lives in its own reservation and is not copied.
* Taking the mark off a one-call def (so its callee builds on the
  caller's tape) fixed every case above, but `def fwd(s); s + "x"; end`
  called in a loop then turned the loop's mark off: each round's
  String.build reservation stayed, `iyi: mapping failed` after ~500k
  rounds. TapeCallGraph took the unmarked def for one that keeps.
  Normalized literals reach the checker as `::String.view("x")`.

Steps, each with its gate:

1. Count the scopes that allocate with their mark off, in std, samples
   and test programs: the refusals step 2 will raise.
2. Mark always on; TapeShrinkChecker's store check (today only for a
   proved `tape do`) in every def, loop round and block; an unproved
   keep is an error naming its safe form (copy_to(owner), a parameter to
   write into, clear and refill, read the value before the loop). Fix
   what std, samples and tests then refuse. csv, xz and tar keep a row's
   Arrays to the program's end today (`mapping failed` past ~500k rows;
   CSVReader's refill assigns `@text = more`): they must free per row.
3. Results in the caller's destination: a one-call def hands it on (the
   callee builds on the caller's tape, and the call graph treats the def
   as transparent); a flat fresh result (String, Array of non-tape
   elements) ending a def after other work moves down to the caller's
   boundary with one memmove; any other implicit result copy is refused
   (SPEC 1.9). RIS_TAPE_STATS counts results moved down (SPEC 6.6).
4. Remove local_tape, its tests (task_local_tape, task_local_tape_helper)
   and the codegen paths for it.
5. Gates: a loop of 1,000,000 rounds whose RSS and mapping count stay
   flat (the a.first and fwd cases above); the File.read wrapper with
   no result copied; pending_result.ri moved to moves, not copies.

## Language and runtime

* Escaping closures outside program and joined task owners: pooled
  environments, including captured receivers; release them with their
  owner, check capture lifetimes and refuse unsupported escapes safely.
  A spawn reached through a proc call is not followed by the capture
  check yet.
* Typed pool validation (SPEC 6.1-6.4): audit remaining bounds,
  overflow, membership, stale views, reset lifetimes and external images.
* FFI paths in use: enforce borrow lifetimes, retained-storage owners,
  foreign-thread attachment and no unwind across foreign frames.
* Runtime pools (test/ris/task_reuse.ri): a long-lived group (a
  server's) or `IyiGroup.new` keeps each task's slot until it ends;
  parallel task fibers are not pooled; a spawned block's captured
  closure data takes program storage per spawn.
* std's long-lived state (HPACK tables, autocert cache, log sinks) into
  typed Pool/SlicePool with explicit free and index links (Goose
  doc/reference/goose/docs/design/owning_dynamic_data.md). Until then
  the no-GC malloc is a bump allocator with the trap off: std never
  frees there (RIS_HEAP_STATS=1 shows it). Then remove the bump
  allocator and restore the trap.
* Error#message answers String, which a program cannot build without a
  heap: let it write into a builder across std.
* Remove general allocator fallbacks and obsolete collector paths from
  ris programs; audit final binaries for collector linkage and heap
  allocator dependencies (the compiler keeps its own GC).
* Stats: RIS_TAPE_STATS owner paths and pool waste (SPEC 6.6).
* A tape hash map laid out as Ruby's Hash (st_table): entries in an
  Array in insertion order, bins an Array(Int32) of indices, String keys
  as views; Copyable like RisTree. Replace the linear-scan TapeMap copies
  in std/yaml, toml, xml and mail. Gate: O(1) lookup on a large map,
  insertion order, zero heap.

## std and benches

* Port the benches to 5.1 task captures. Left: tls (server task takes
  the caller's TlsServerConfig/TlsConfig: a Copyable or Share config, or
  one server task per section), udp:274 (socket shared by a receive task
  and the caller), dns:951 (server task and client share `log` and
  sockets), http.iyi:2154 (serve's `handle`) and sse.iyi:513
  (`Response.stream`'s block) as opaque callback effects, sse.iyi:543
  (Hash shrink while copying headers per reconnect), std_compress's
  `Inflater.new { feed.next }` (an opaque source proc).
* http_latency, http_resume, http_stop check in 64-79 s and stop at the
  shrink refusal http_continue has. acme, http2_exercise and
  std_http_exercise.sh still call the removed HTTP.tls_config=.
  TlsConfig reads the system roots per handshake: make Certificate
  copyable to Program.tape to keep them once.
* HTTP answer's slow request path still uses String-based read_head and
  body readers; migrate before claiming chunked/Expect/HTTP/1.0 parity
  without a heap. Recheck prefork, TLS and samples/ris/web.
* Bench ports left: mail (String#to_unsafe), toml/yaml (Any: retire for
  TapeValue), xml (Document, Node: XmlTree now), zstd, bzip2 (imports
  std/random through static_array > slice > indexable: move `sample`),
  and the std/gc importers (format, socket, big, csv, std, file,
  file_utils, fuzz, http, io, json, png): replace GC.stats with
  RIS_HEAP_STATS=1 on the run, as std_netip_exercise.sh does.
  server_load proves collections: drop or rewrite it. Builds still stop
  on pointer helpers (slice, png, zstd, dns, hpack), Arrays of growing
  values (set, otp, idna, hpke, x509, ct_timing) and General allocation
  (number_format, reference_storage, env, thread_floor).
* format's two-word cost proof needs a side-reservation count (bignum
  words are side Arrays); float.iyi's parser has a copy in tape.iyi:
  merge them.
* Autocert part B: bench/std_autocert_exercise.iyi and its driver, with
  real TLS deadline and parallel-server cases, Pebble, restarts and
  mutation checks (part A's gates: test/ris/autocert.ri, autocert_wire.ri).
* std_process: the `handlers` mutation proof (child keeps this program's
  TERM handler) is not caught.
* Add 128-bit formatting, IDNA and URI resolution.

## Known failures

* check.sh (2026-10-31): samples/ris/web prints `000` (no answer);
  http_answer_scope panics `cannot create a socket: error 24` (EMFILE),
  also run alone and already at d056d2aa2.
* compiler_spec does not build: spec/compiler/iyi_import_spec.cr calls
  artifact_signature, removed in d5742ac68. Before that: 58 failures,
  427 errors in 93 files (General allocation unavailable, Crystal
  prelude requires, missing exception types).
* bench/concurrency_exercise.sh needs `ulimit -n 8192` and is not in
  check.sh; recheck after runtime changes.
* bench/parallel_exercise.iyi:124 (a task value's Panicked arm) and
  bench/metric/metric.iyi (Array of the tape type Planet) do not
  typecheck.
* bench/std_websocket_exercise.iyi appends to an `io` builder and reads
  it back: move it to a String local, then recheck the artifact
  comparison.
* spec/compiler/iyimod_spec.cr's getter/defer case cannot resolve
  `Pointer(RisArrayPool(String))` from boot/shelf's type ids.
* bench/socket_exercise.sh: several mutations are not caught; a
  unix-socket mutation fails with "the address is in use".
* The mutation phases of std_acme, cookie, router, sse and websocket .sh
  run past 20 minutes; check whether they finish.
* base64's timing ratio fails under load.
