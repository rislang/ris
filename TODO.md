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
2. Checker errors (wrong refusals, holes, the literal String's run-time
   error, SocketError in a socket union): the ones programs hit first
   come first.
3. SPEC 3.3 alias question (`clear` of an Array a local aliases),
   decided with EGM.
4. test/ris/sse.ri, then HTTPClient's pooling.
5. Tighten heap_trap.
6. A gate on the checker `evaluate`'s stack use.
7. Benches as one item.
8. Speed.
9. Language and runtime.
10. std.
11. macOS arm64.
12. Known failures.

Speed work stays out of minitest. The jq check at jqg.ri:424 is the
maintainer's.

## The user's programs

Each obstacle a program under ~/contribute/rispacks hits, with a repro.

* Checking time doubles per nested block: each loop's two final
  rounds re-walk every inner block and keep their events, so a body d
  blocks deep costs 4^d walks. web's examples/testing_test.ri checks
  for 1182 s, web/static_test.ri for 11 min. Caching alone does not
  help: events and the final pairing pass still grow 2^d. Plan, gate
  and open questions: doc/drafts/checker-nested-blocks.md (EGM review
  first).

## Checker errors

Code to the new SPEC (1.1, 1.5, 1.9, 2.1, 3.2, 3.3, 3.5, 3.6); breakage
between steps is fine; no transition stages.

Fewest tokens: the compiler's refusals are the list. One task per
clone (ris1/2/3) and per cluster below; build with
`RIS_SCOPE_ERRORS=all ris build --no-codegen x.ri` to see every
refusal of a file at once, fix by message, rerun only that cluster's
files; one full check.sh on minitest per finished step, not per fix.

Checker holes (unknown must be refused, SPEC 3.6) and wrong refusals:

* A struct whose constructor makes its own data is refused at a store
  past its round only with no owner argument: one given an Array or Hash
  it reads, or a builder, pool or class it does not allocate through, is
  still taken by the older rule. Follow where the constructor allocates.

* `def load(t : String) : T; T.from_json(t); end` builds: an @[OnTape]
  struct's String may view the document's decoded text, in load's scratch.

* An untyped class default still loses its roots at a cycle store
  when the def answers the Array it stored into: in
  refused/cycle_default_untyped, `def node(a = -1, v = C.new)` with the
  body `@nodes << v` and `node(b).size` in pipe passes; ending node with
  `0` is refused. In the checking pass the call's store holds an untyped
  root that `placed` does not find in @default_roots. Track the default
  at the call.

* A store into `self`'s field inside a method is not checked against
  the method's scope; the same store is refused at a caller that holds
  the receiver in a local. Check it where it is made.


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
* A `tape` block's value is checked as leaving even where the tape
  call's own value is dropped: such blocks end with `nil` to pass.
* Call summaries model text a callee builds from its inputs
  (interpolation, inspect) as a view of them; tape_text now adds a
  fresh root for an allocating String call not known to answer a view.

## SPEC 3.3 alias question

Decide with EGM, then gate:

* SPEC 3.3: `v = w.rows`, `w.rows.clear`, `puts v.size` passes: a view
  taken through a getter stays live over the clear. Refuse it.

## sse.ri and HTTPClient pooling

* HTTPClient's ordinary open/request pooling needs an exchange used for
  more than one request, and the checker refuses that: a second
  `open_at_into` (or `open_into`) over one RisHttpClientExchange fails
  with "cannot shrink tape storage with a live view of
  Response.@held.@line_values" (via begin_client -> clear), even with a
  constant block in a def. Repro:
  `def s(st : RisHttpClientExchange, u : String) : Int32`,
  `got = HTTP.open_at_into(st, "127.0.0.1", "GET", u) { |r| 1 }`,
  `got.is_a?(Int32) ? got : -1`, `end`; then
  `st = RisHttpClientExchange.new(Response.new(0))` and two `s(st, ...)`
  calls. The exchange's own @response is taken as a live view at the
  next request's clear: a checker change. After it: HTTPClient owns one
  exchange per pooled connection with `@idle` as indexes into them, not
  `{String, Conn}` made per request; SSE.open keeps one exchange beside
  its parser; gate: two requests over one connection, `reused` 1.
* Response.stream is refused ("cannot return a value made in this def
  `stream`'s scratch", SPEC 1.9): the response keeps the writer proc.
  SSE.stream and every streaming handler are refused with it.

## Tighten heap_trap

`heap_trap` (`test/ris/check.sh:29`) passes on any compile error naming
String, Array, Hash or tape, so it can hide a refusal: tighten it.

## Checker evaluate stack

The checker's `evaluate` uses a lot of stack: small changes must not
decide whether it fits. Add a gate on its stack use.

## Benches

* Benches: build each, group the refusals by message, fix per group.
  Known before the new rules: 5.1 task captures (tls server configs,
  udp:274, dns:951, http.iyi:2154 serve's `handle`, sse.iyi:513 and :543,
  std_compress's opaque source proc); HTTP.tls_config= removed but
  still called by acme, http2_exercise and std_http_exercise.sh; std/gc
  importers and server_load drop it.

Then remove to_heap and its mark:

No rule needs them (SPEC_CHANGELOG 2026-11-02). Remove the method
(`src/iyi/tape.iyi`), `@[TapeToHeap]`, the census's `to_heap` and
`@[TapeToHeap]` reasons, the checker exemptions (`tape_shrink_checker.cr`;
that they cannot dangle is unproved), test, bench and doc uses and the
`to_heap.ri` gate. Make `call_error.cr:740,839` and `tape_spec.cr` name
`copy_to`. Gate: no `to_heap` or `TapeToHeap` left outside doc/archive.


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

## std

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

## Known failures

* Every growing tape value reserves 128 MiB of address space, even a
  128-byte builder (region.iyi:367-370, 523-535). Under
  `vm.overcommit_memory=2` each is charged: a FileServer answer holds
  up to eight (doc/drafts/fileserver-outgoing.md, Memory).
* Compiler: an inline argument stored as a view escapes SPEC 1.1/3.6.
  `k.put("<" + n.to_s + ">")`, where `put` stores `value.as_tape` in
  a field, compiles, and the field dangles once the def returns; the
  same value in a local is refused. Seen in Outgoing#header
  (doc/drafts/fileserver-outgoing.md, P1). Suspect: tape_text,
  src/compiler/iyi/semantic/tape_shrink_checker.cr:514-548. The fix
  commits five programs under test/ris/refused/ and their expect
  lines after check.sh:64:
    expect inline_view_concat 'cannot store data made in this def'
    expect inline_view_interp 'cannot store data made in this def'
    expect inline_view_call 'cannot store data made in this def'
    expect inline_view_instance 'cannot store data made in this def'
    expect inline_view_class 'cannot store data made in this def'
* check.sh needs `ulimit -n 65536`: without it http_answer_scope and
  samples/ris/web fail (`bin/minitest-check check` does not set it).
* std_spec: process_spec.cr:196 timed out at 60 s on CI once (de771de49)
  and passed on a rerun.
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
