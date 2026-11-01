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

4. samples and tests, group by group, then one full check.sh.
   `RIS_SCOPE_ERRORS=all ris build --no-codegen x.ri` lists every scope
   refusal. Done: csv/xz/tar/bzip2, query, http_head, uri, idna,
   socket's address parsing, base32, shlex, uuid, path, ini, mime, otp,
   format, deque, set, slice, string_pool, json's writer, file info and
   realpath, curve25519, mlkem, capsule, bit_array, time's RFC 3339. Patterns: read into one flat String
   (tagged with a 0 or 1 byte where an error may come back), then wrap
   it in a one-call def, a choice of two calls, or a `new`.
   Left, by test: socket.iyi's resolver (resolve, lookup, ask_upstreams,
   ask_upstream keep each round's answers: socket_pair, socket_pieces,
   websocket_*, smtp, mail, dns, secure_dns, udp, http_*, samples/ris/*),
   yaml/toml/xml/xpath parsers (values built across scopes), regex
   (RxCompiler fields), hpack (decode_fields), zip, big, png, eiy, log
   (with_context fields), heap, roots_holders, text_grow, slice_pool,
   task_* (spawn block values, see below).
5. benches: build each, group the refusals by message, fix per group.

Checker holes found on the way (unknown must be refused, SPEC 3.6):

* A spawn block's non-flat value (a Tuple or Hash, task_tape_result)
  is refused: the block frees its scratch before the task copy takes
  the value. Copy the value at the boundary before the reset.
* File::LibC.realpath (a @[TapeUnsafe] def in a `{% if %}` branch)
  set outer locals to text made in a loop round, unrefused: the round
  freed it and real_path answered garbage. Find why that body is not
  checked (the same code in a program is refused).
* A tape block in a constant's initializer (program_local_init:
  `INIT = tape { State.keep(String.new("x")) }`) stores block text into
  a class variable unrefused.
* The call graph's `fresh?` takes a call's String-or-error union as
  fresh when any path allocates (an error sentence's interpolation),
  though every String it answers views the parser (toml's
  basic_string now writes into the parser's @texts): scalar's
  `TapeAny.new(basic_string!)` is refused. Narrow by summary.
* Field paths fold at FIELD_DEPTH (now 6, was 4): a deeper path through
  a reader's own fields (entry.@reader.@inflater.@core.@chunk) conflates
  a refill with views of its siblings. Fold by type, not depth.
* A String local's `<<` is lowered to `__ris_append` unless the local is
  growing; that result views the argument, so a block appending to an
  outer String is refused. Lend the local to a builder parameter.
* A one-call def's value moves down only when it is one fresh flat
  value: a tuple or two locals do not. Bzip2.decompress tags its String
  (a 0 or 1 byte first) to answer bytes or an error in one value.
* A value a marked def yields to its caller's block may be its scratch,
  but the block sees it as a view of the call's inputs, so it may store
  it outward (CSV.parse's row before this change): mark yielded values
  as the yielding scope's.
* Call summaries model text a callee builds from its inputs
  (interpolation, inspect) as a view of them; tape_text now adds a
  fresh root for an allocating String call not known to answer a view.

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

* RisScopeMove keeps a def's scratch when its fresh result does not fit
  on the marked mapping or its Array payload is on a mapping the scope
  grew onto; a loop's `break` with a value and a block's `break` skip
  their scope's reset. Free those too (SPEC 1.1).
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

* check.sh (2026-11-01, 3a4b4810b): 63 FAILED. Every scope frees now;
  std, samples and tests that keep scratch past a scope or return a
  non-flat value made in a def are refused until steps 4-5 migrate them
  (see step 4's list).
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
