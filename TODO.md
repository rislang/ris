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

Breakage between steps is fine; no transition stages.

Fewest tokens: the compiler's refusals are the list. One task per
clone (ris1/2/3) and per cluster below; build with
`RIS_SCOPE_ERRORS=all ris build --no-codegen x.ri` to see every
refusal of a file at once, fix by message, rerun only that cluster's
files; one full check.sh on minitest per finished step, not per fix.
Fix a checker hole below only when a cluster hits it.

5. Benches: build each, group the refusals by message, fix per group.

Trial programs (samples/ris/trial/blocked/ has the repros), most blocking
first; samples/ris/trial/run.sh is their gate:

* `HTTP.get` answers an empty body with its headers; maybe http_coding's.
* `OptionParser` cannot set a String option; `ris doc std/http` fails;
  Tuple has no `<` for sort_by; `out` as a name gets an unclear error;
  LEARN.md lacks `Program.args` and `import std/int`.

* json_buffer FAILED: PullParser's `initialize` calls `read_next`, refused
  by SPEC 2.2, so `PullParser.new` does not compile. Read lazily or make
  the first read a separate call; fix the test's old API with it.
* bench/std_json_exercise.iyi has 2 lines on JSON's old API.

Checker holes found on the way (unknown must be refused, SPEC 3.6):

* `h.update(k) { |v| w.downcase }` builds: Hash keeps the block's value,
  made in a block round. Any other runtime def keeping a block's value too.
* A yield is judged per def, not per argument: `each_field`'s name is a
  view, its joined value is fresh, and storing either is refused.
* test/ris/sse.ri is refused and is not in check.sh: EventParser replaces
  `@line` and `@data` with a new builder in a round, and keeps `@type` and
  `@id_buffer` from `SSE.clean`'s scratch. Give them stable storage.

* `def load(t : String) : T; T.from_json(t); end` builds: an @[OnTape]
  struct's String may view the document's decoded text, in load's scratch.

* An unmarked one-call def with an untyped class default still loses
  that default's roots at a cycle store. A body containing only
  `@nodes << v` in `def node(a = -1, v = C.new)` passes; the marked
  two-expression body is now refused. Track the default at the call.

* SPEC 3.3: `v = w.rows`, `w.rows.clear`, `puts v.size` passes: a view
  taken through a getter stays live over the clear. Refuse it.
* `IyiSocket.listen_result` answered a socket made after other work
  inside a union (`IyiSocket | SocketError`), unrefused; the socket was
  freed with the def and every worker accepted on fd 0. Refuse a class
  instance made in a def and answered in a union after other work.
* A store into `self`'s field inside a method is not checked against
  the method's scope; the same store is refused at a caller that holds
  the receiver in a local. Check it where it is made.

* A multi-expression def answering RisBoard.take's non-flat message
  can lose its decoded payloads when its scratch ends, unrefused
  (autocert's reader_settings). Attribute decoded data to its receiving
  scope; the one-call constructor form now keeps that gate safe.
* HTTPClient's ordinary open/request pooling still needs transport
  storage supplied by its caller. DoH now retains an explicit exchange
  owner and uses HTTP.open_at_into; a request-local Conn cannot be kept
  in a longer-lived client's idle list.

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
* text_grow: `field.take_event(Program.tape)` returns
  `GrowingTextEvent.new(@text).copy_to(owner)`, yet the caller sees the
  event as a live view of `field`'s text, so the later rebind is refused
  as a shrink. A callee's copy_to result is not a view of its input.
* A String local that starts as a literal (`text = "head:"`) and grows
  in a block (`100.times { text << i }`) fails at run time: "tape side
  reservation exhausted: 20". `text = ""` then `text << "head:"` works.
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

## Speed

At the end of each Now step, run ris-bench's `goose-evals.sh medium`
(the goose-evaluations ports jq, json, ninja and yaml against Goose)
and put one line per port in the step's commit body. The items below
are taken by the maintainer for now; others time, but leave them.
x = ris time / Goose time, median of 5 runs; lower is faster. A
timing is a baseline and never fails a gate; nothing is timed per
change. Gates stay structural. No item below changes SPEC.

* A loop or block nested in a def keeps its scope mark even when it
  puts nothing on the tape. TapeScopeChecker
  (src/compiler/iyi/semantic/tape_scope_checker.cr) turns a mark off
  when `allocates?` finds no tape growth, but it reaches only each
  def's top body and the program's top level: Finder does not enter
  a def, so its nested While and Block never reach `off`. Each round
  then loads the tape's region, cursor and side and may call
  `__iyi_scope_release`. perf (ris 0ad4691bb): jq
  `Engine#scan_string` is 25-33% of jq's time, mostly that compare;
  yaml `Document#skip_spaces` spends 15-20% on it. Send nested loops
  and blocks through the same check. If scan_string still keeps its
  mark, find what `allocates?` counts there. Gate: IR specs that a
  byte loop in a def has no mark and a loop in a def that pushes to
  a Builder keeps it; check.sh and RIS_TAPE_STATS unchanged.
* String#hash (src/iyi/tape.iyi:218) is byte-at-a-time FNV-32. perf
  on ninja gen-small: `Hash#find` is 34% of the run, 70% of it
  hashing; ninja is at 1.40x. Hash 8 bytes a step like Goose
  (doc/reference/goose/docs/stdlib.md, Hashing), never read past a
  short String's end (it may end before a guard page), and spread
  the result into the low bits the table masks. Hash iterates in
  insertion order (SPEC 7.2), so programs see no change. iyi has the
  same FNV: list it in UPSTREAM.md. Gate: std hash/Hash specs; equal
  copies and views hash equal; strings differing in one byte at each
  position 0-17 hash differently; keys k0..k999 spread over the low
  bits; a String ending at a page boundary hashes without a fault.

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
* std's long-lived state (HPACK tables, autocert cache, HTTPClient ticket
  origins, log sinks) into typed Pool/SlicePool with explicit free and
  index links (Goose
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

## Remove to_heap and its mark

No rule needs them (SPEC_CHANGELOG 2026-11-02). Remove the method
(`src/iyi/tape.iyi`), `@[TapeToHeap]`, the census's `to_heap` and
`@[TapeToHeap]` reasons, the checker exemptions (`tape_shrink_checker.cr`;
that they cannot dangle is unproved), test, bench and doc uses and the
`to_heap.ri` gate. Make `call_error.cr:740,839` and `tape_spec.cr` name
`copy_to`. Gate: no `to_heap` or `TapeToHeap` left outside doc/archive.

`heap_trap` (`test/ris/check.sh:29`) passes on any compile error naming
String, Array, Hash or tape, so it can hide a refusal: tighten it.

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
