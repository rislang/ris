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
* Linux x86_64 and aarch64, macOS arm64 (SPEC 7.1): no other targets.

## Order of work

Testing ris programs can start now: what a program hits comes first.
The items are below; this is only their order.

1. The user's own ris programs: each obstacle becomes an item here.
2. TlsClient's ticket and SocketError in a socket union.
3. Holes: `T.from_json` in a def, `Hash#update`'s block value,
   RisBoard.take's result.
4. Holes: SPEC 3.3 `clear`, a store into `self`'s field, a tape block
   in a constant, the one-call def's default, `flat_result?` callers.
5. Wrong refusals and the literal String's run-time error: when a program
   hits one.
6. test/ris/sse.ri, then HTTPClient's pooling.
7. Tighten heap_trap.
8. The checker's `evaluate` uses a lot of stack: small changes must not
   decide whether it fits.
9. Step 5: benches. Then remove `to_heap` and `@[TapeToHeap]`.
10. std additions, language and runtime, other known failures.

Speed work stays out of minitest. The jq check at jqg.ri:424 is the
maintainer's.

## Now: code to the new SPEC (1.1, 1.5, 1.9, 2.1, 3.2, 3.3, 3.5, 3.6)

Breakage between steps is fine; no transition stages.

Fewest tokens: the compiler's refusals are the list. One task per
clone (ris1/2/3) and per cluster below; build with
`RIS_SCOPE_ERRORS=all ris build --no-codegen x.ri` to see every
refusal of a file at once, fix by message, rerun only that cluster's
files; one full check.sh on minitest per finished step, not per fix.
Fix a checker hole below only when a cluster hits it.

5. Benches: build each, group the refusals by message, fix per group.

Checker holes found on the way (unknown must be refused, SPEC 3.6):

* OptionParser.parse given an `args` shorter-lived than `found` is
  refused at the append inside std/option_parser, with a generic message:
  the refusal belongs at the caller's `parse` line
  (doc/drafts/option-parser/probes/p14d.ri).
* `h.update(k) { |v| w.downcase }` builds: Hash keeps the block's value,
  made in a block round. Any other runtime def keeping a block's value too.
* A yield is judged per def, not per argument: `each_field`'s name is a
  view, its joined value is fresh, and storing either is refused.
* test/ris/sse.ri is refused and is not in check.sh: EventParser replaces
  `@line` and `@data` with a new builder in a round, and keeps `@type` and
  `@id_buffer` from `SSE.clean`'s scratch. Give them stable storage.

* An `Any` made in a round and pushed onto an outer `Array(Any)` builds
  and dies of a memory fault: `1000.times { |i| h = {} of String => Any;
  h["x"] = Any.new(i); objects << Any.new(h) }`.
* A def with several returns loses what its answer views: read_union's
  `Array(String)` member was taken as made in its caller's scratch and
  refused (SPEC 1.9); std/json reads it by a tail call instead.

* `def load(t : String) : T; T.from_json(t); end` builds: an @[OnTape]
  struct's String may view the document's decoded text, in load's scratch.

* An unmarked one-call def with an untyped class default still loses
  that default's roots at a cycle store. A body containing only
  `@nodes << v` in `def node(a = -1, v = C.new)` passes; the marked
  two-expression body is now refused. Track the default at the call.

* SPEC 3.3: `v = w.rows`, `w.rows.clear`, `puts v.size` passes: a view
  taken through a getter stays live over the clear. Refuse it.
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
* A SocketError in a union with IyiSocket, made in a round and kept, is
  not refused: a connect's union is exempt for the socket's sake.
* TlsClient keeps a resumed ticket with `copy_to(Program.tape)`: the
  program tape grows per resumption. Give the client a slot to refill.
* A class instance made in a def and returned after other work was
  taken as flat (no tape fields): UdpSocket.bind? answered a freed
  socket. Now refused; check other `flat_result?` callers.
* A block's value that its yielder discards (`each`, `tape`) is still
  checked as leaving: blocks end with `nil` to pass. Skip the check when
  the yielder ignores the value.
* Call summaries model text a callee builds from its inputs
  (interpolation, inspect) as a view of them; tape_text now adds a
  fresh root for an allocating String call not known to answer a view.

## macOS arm64

SPEC 7.1 lists it; these are what Linux has and it lacks yet.

* Measure pages returned to the OS: scope_frees.ri and fibers/spares.ri read
  /proc, and `MADV_FREE` is lazy, so resident size may not fall. Decide
  between `task_info` with `MADV_FREE_REUSABLE`, or `mmap` over the range.
* Port the other checks in `ris-macos.yml`'s `RIS_CHECK_SKIP`: file_copy_to.ri
  and tls_session_tickets.ri.
* Short frame names in a backtrace, then drop check.sh's `frame_edge`.
* A tarball, its release job and `install_ris.sh`: static LLVM fails there.
* Run a reservation-heavy program on a small Mac: `MAP_NORESERVE` is a no-op.

## Speed

At the end of each Now step, run ris-bench's `goose-evals.sh medium`
(the goose-evaluations ports jq, json, ninja and yaml against Goose)
and put one line per port in the step's commit body.
x = ris time / Goose time, median of 5 runs; lower is faster. A
timing is a baseline and never fails a gate; nothing is timed per
change. Gates stay structural.

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
