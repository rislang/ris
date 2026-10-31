# ris TODO

How to work (fewer tokens, faster to the goal):

* Demand first: take the largest gap to SPEC in an existing workload.
  For an uncovered language guarantee, add a small representative gate.
* One change, one relevant gate: check the promised behavior, including
  error paths.
* Replace, don't wrap: when a String API has a tape twin, grep the repo
  for callers. Few: move them and delete the String API in one commit.
* TODO holds open work only, one item per task; completed work lives in
  git log. Remove an item when its guarantee passes its gate.
* Linux x86_64 and aarch64 only (SPEC 7.1): no work for other targets.

## Now: every scope frees (SPEC 1.1, 1.5, 1.9, 3.2, 3.5, 3.6)

Breakage between steps is fine; no transition stages.

1. Gates first (they fail until step 2): the a.first loop and the fwd
   loop below, 1,000,000 rounds, RSS and mapping count flat; the
   File.read wrapper with no result copied (RIS_TAPE_STATS).
2. One compiler change:
   * TapeScopeChecker.mark puts the mark on always; safe? and decide go.
   * TapeShrinkChecker's store check (today only for a proved `tape do`)
     runs in every def, loop round and block; what it cannot prove is
     refused with its safe form (copy_to(owner), a parameter to write
     into, clear and refill, read the value before the loop). Unknown is
     refused, never allowed: a freed scope must not leave a live view.
   * A call is a read by its type, not by a READS list: one that returns
     no tape value, or a view, reads. Otherwise `a.first` is refused.
   * local_tape, its codegen and its tests (task_local_tape,
     task_local_tape_helper) are removed.
   * __iyi_scope_result's staged copy goes: a one-call body hands the
     destination on (no mark on that def); a flat fresh result (String,
     Array of non-tape elements) ending a def after other work moves down
     to the caller's boundary with one memmove; any other implicit
     result copy is refused (SPEC 1.9). RIS_TAPE_STATS counts results
     moved down (SPEC 6.6). pending_result.ri checks moves, not copies.
3. std: `ris build --no-codegen test/ris/std_text_plain.ri` compiles
   every module; group the errors by message and fix each group in one
   pass. csv, xz and tar then free each row (CSVReader's refill assigns
   `@text = more` today, which keeps a row's Arrays to the program's end).
4. samples and tests: RIS_CHECK_MATCH per group, then one full check.sh.
5. benches: build each, group the refusals by message, fix per group.

Measured on the old rules (1,000,000 rounds in one `tape do`):

* `t = a.first * 100` in a loop body: 2.1 GB RSS (`first` is not in
  READS, so the body was taken to read outer tape and kept its
  scratch). The same in a def: 266 MB. A def that frees: 7.6 MB.
* A def's fresh result was staged by `__iyi_scope_result` and copied
  back twice: `def f(p); File.read(p); end` on a 21 MB file took 41 ms
  and 16,232 page faults, `File.read(p)` called directly 15 ms and
  5,540. Same for `a + "x"`, interpolation, `String.new(a)`,
  `Array(UInt8).new(n) { }`, `def f; g; end`. A local grown in place
  (`w = ""; w << x; w`) lives in its own reservation and is not copied.
* With only the one-call def's mark taken off, `def fwd(s); s + "x";
  end` called in a loop turned the loop's mark off: each round's
  String.build reservation stayed, `iyi: mapping failed` after ~500k
  rounds. With the mark always on this cannot happen. Normalized
  literals reach the checker as `::String.view("x")`.

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
  doc/reference/goose/docs/design/owning_dynamic_data.md).
* Stats: RIS_TAPE_STATS owner paths and pool waste (SPEC 6.6).
* A tape hash map laid out as Ruby's Hash (st_table): entries in an
  Array in insertion order, bins an Array(Int32) of indices, String keys
  as views; Copyable like RisTree. Replace the linear-scan TapeMap copies
  in std/yaml, toml, xml and mail. Gate: O(1) lookup on a large map,
  insertion order.

## std and benches

After the Now steps; their refusals replace most of the old bench list.

* Benches: build each, group the refusals by message, fix per group.
  Known before the new rules: 5.1 task captures (tls server configs,
  udp:274, dns:951, http.iyi:2154 serve's `handle`, sse.iyi:513 and :543,
  std_compress's opaque source proc); HTTP.tls_config= removed but
  still called by acme, http2_exercise and std_http_exercise.sh; std/gc
  importers and server_load drop it.
* HTTP answer's slow request path still uses String-based read_head and
  body readers. Recheck prefork, TLS and samples/ris/web after it.
* TlsConfig reads the system roots per handshake: make Certificate
  copyable to Program.tape to keep them once.
* float.iyi's parser has a copy in tape.iyi: merge them.
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
