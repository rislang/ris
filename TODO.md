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

## Now: code to the new SPEC (1.1, 1.5, 1.9, 2.1, 3.2, 3.3, 3.5, 3.6)

Breakage between steps is fine; no transition stages. Steps 1 and 2
and step 4's clusters not marked "After step 1" can run in parallel
(different files); step 3 and the marked clusters follow 1.

Fewest tokens: the compiler's refusals are the list. One task per
clone (ris1/2/3) and per cluster below; build with
`RIS_SCOPE_ERRORS=all ris build --no-codegen x.ri` to see every
refusal of a file at once, fix by message, rerun only that cluster's
files; one full check.sh on minitest per finished step, not per fix.
Fix a checker hole below only when a cluster hits it.

2. Docs to the SPEC (doc-only: no build, no check.sh). Run
   `/egm:egm-drift-report` on AGENTS.md, LEARN.md, README.md and
   UPSTREAM.md (CONTRIBUTING.md, Design checks) and fix the drift; the
   report is a worksheet, not committed. Also rewrite doc/TAPE_API.md's
   owner section for 2.1 and rename Str/Ary/Tre to String/Array/RisTree
   in README.md, CONTRIBUTING.md, LEARN.md, UPSTREAM.md, LLVM.md,
   doc/TAPE_API.md, doc/STD_PORT.md and doc/MESSAGES.md (check each hit
   is the old type name). Lines at most 80 characters.
3. Shrink through an owner's field (SPEC 3.3), after 1:
   test/ris/refused/owner_shrink_*.ri compile today (a loop reads
   `vars.vals[i]` while the field, or an alias of the owner, clears
   it; only the bounds check stops it). Refuse each with 'cannot
   shrink tape storage with a live view', then add them to check.sh.
   Same for test/ris/refused/array_view_argument_shrink.ri: an
   Array::View a def returns is not seen as live, and check.sh does
   not run the file.
4. Samples and tests, group by group, then one full check.sh.
   `RIS_SCOPE_ERRORS=all ris build --no-codegen x.ri` lists every scope
   refusal. check.sh: 41 FAILED. Patterns that work: read into one flat
   String (tagged where an error may come back) and wrap it in a one-call
   def, a choice of two calls, or a `new` (a constructor builds in the
   caller's scope: dns, SvcbRecord, json's document); keep a round's
   texts in a builder made before the loop (`DnsLookup`, `kept`);
   refill a field instead of a new value (TLS records, key updates); a
   struct or Tuple of texts and plain values moves down whole.
   Left, by cluster:
   * After step 1: HTTP client and server (answer, http_*, server_*,
     serve full loop, websocket_*, samples/ris/web, heap_check): objects
     made in helpers and stored lazily into longer-lived ones
     (BodyReader's decoders, Response bodies, h2 state, hpack
     decode_fields, zstd). Make each holder an owner class built in its
     owner's scope (SPEC 2.1), so helpers fill its fields in place.
   * After step 1: TlsSession keeps each ticket with
     `copy_to(Program.tape)`, growing per ticket. Make the session an
     owner class with a ticket field refilled in place.
   * socket_pair, socket_pieces, socket_race, smtp, mail: connect's
     attempt list (socket.iyi 248, 1066), ResolvConf parsing (dns.iyi
     1340s), `Resolver.system` made in a def.
   * After step 1: yaml/toml/xml/xpath parsers: trees built across defs; toml's
     SlicePool::List state now lives in its pool, the rest is open.
   * regex (RxCompiler fields), big (BigInt results), png (chunk texts
     kept per round, PngInfo built in its def), zip, log (with_context
     fields), hpack, text_grow, roots_holders, iyimod_text_growth,
     autocert, program_local_init, fix array_refill, secure_dns.
5. Benches: build each, group the refusals by message, fix per group.

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
* A value made in a `while` condition (`while got = f(...)`) is freed
  with the round but not attributed to it: DnsName.candidates stored
  each round's String in an outer Array unrefused and read garbage.
* A class instance made in a def and returned after other work was
  taken as flat (no tape fields): UdpSocket.bind? answered a freed
  socket. Now refused; check other `flat_result?` callers.
* A block's value that its yielder discards (`each`, `tape`) is still
  checked as leaving: blocks end with `nil` to pass. Skip the check when
  the yielder ignores the value.
* Call summaries model text a callee builds from its inputs
  (interpolation, inspect) as a view of them; tape_text now adds a
  fresh root for an allocating String call not known to answer a view.

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
