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

## 0.1.0 blockers (decided 2026-11-10)

What CHANGELOG's 0.1.0 promises must work; the items stay in their
sections below and are listed here in order:

* Checking time per nested block: testing_test.ri now checks in 16 s;
  time web/static_test.ri once it builds (it fails: web/spec import
  before the first `spec` block, a web-side change).
* Benches build (section 7), including `HTTP.tls_config=` callers.
* compiler_test passes: fix its 225 failures and two segfaulting
  groups (section 12).
* Release: Linux tarball and its job, `install_ris.sh`, tag v0.1.0;
  `ris --version` prints 0.1.0.

## 1. Programs first

* std on the tape, found porting the HTTP handlers (drift report in
  doc/drafts/server-answer-features.md): Router's `Pattern.parse` (SPEC
  1.9, router.iyi:189), the HTTPS client (`records_handshake` returns
  an owner, http.iyi:4847; blocks samples/iyi/autocert.iyi),
  `Zstd.decompress` (view check, zstd.iyi:1410), `Cookie.parse_header`
  and `HTTP.cookie_pairs` (a Hash from a def). Then give `Incoming`
  back `form`, `multipart` and `cookies`, which `Request` had.

* The user's own ris programs: each obstacle becomes an item here.

Breakage between steps is fine; no transition stages.

Fewest tokens: the compiler's refusals are the list. One task per
clone (ris1/2/3) and per cluster below; build with
`RIS_SCOPE_ERRORS=all ris build --no-codegen x.ri` to see every
refusal of a file at once, fix by message, rerun only that cluster's
files; one full check.sh on minitest per finished step, not per fix.
Fix a checker hole below only when a cluster hits it.

## 2. Checker holes (ordered: those programs hit first)

Unknown must be refused (SPEC 3.6).

* A String local's `<<` is lowered to `__ris_append` unless the local is
  growing; that result views the argument, so a block appending to an
  outer String is refused. Lend the local to a builder parameter.

* A `tape` block's value is checked as leaving even where the tape
  call's own value is dropped: such blocks end with `nil` to pass.

* An untyped class default still loses its roots at a cycle store
  when the def answers the Array it stored into: in
  refused/cycle_default_untyped, `def node(a = -1, v = C.new)` with the
  body `@nodes << v` and `node(b).size` in pipe passes; ending node with
  `0` is refused. In the checking pass the call's store holds an untyped
  root that `placed` does not find in @default_roots. Track the default
  at the call.

* A refill under a branch in a loop is refused as clearing a view an
  earlier round left: a class whose `@names` view its own `@text`,
  refilled (`@text.clear; @names.clear`, then appends) through
  `if c = client; c.refill; end` in `2.times`, then `client` read, is
  refused at the clear. The else path keeps the slot the then path
  emptied, and the next round's use carries the old view, born before
  that round's clear. No path holds it: kill the view with its slot.

* A one-call def's value moves down only when it is one fresh flat
  value: a tuple or two locals do not. Bzip2.decompress tags its String
  (a 0 or 1 byte first) to answer bytes or an error in one value.

* A def with several returns loses what its answer views: read_union's
  `Array(String)` member was taken as made in its caller's scratch and
  refused (SPEC 1.9); std/json reads it by a tail call instead.

* A struct whose constructor makes its own data is refused at a store
  past its round only with no owner argument: one given an Array or Hash
  it reads, or a builder, pool or class it does not allocate through, is
  still taken by the older rule. Follow where the constructor allocates.

* The call graph's `fresh?` takes a call's String-or-error union as
  fresh when any path allocates (an error sentence's interpolation),
  though every String it answers views the parser (toml's
  basic_string now writes into the parser's @texts): scalar's
  `TapeAny.new(basic_string!)` is refused. Narrow by summary.

* text_grow: `field.take_event(Program.tape)` returns
  `GrowingTextEvent.new(@text).copy_to(owner)`, yet the caller sees the
  event as a live view of `field`'s text, so the later rebind is refused
  as a shrink. A callee's copy_to result is not a view of its input.

* A spawn block's non-flat value (a Tuple or Hash, task_tape_result)
  is refused: the block frees its scratch before the task copy takes
  the value. Copy the value at the boundary before the reset.

* OptionParser.parse given an `args` shorter-lived than `found` is
  refused at the append inside std/option_parser, with a generic message:
  the refusal belongs at the caller's `parse` line
  (doc/drafts/option-parser/probes/p14d.ri).

## 3. SPEC 3.3 alias clear (EGM decision)

* SPEC 3.3: `v = w.rows`, `w.rows.clear`, `puts v.size` passes, as
  does the same with a local `v = a`. v aliases the Array handle (SPEC
  1.4) and reads size 0: nothing dangles. A view through the getter
  (`w.rows[0]`, `w.buf.finish`) is refused. Whether an alias is a 3.3
  "holder" a clear must refuse is a SPEC question: decide it (EGM),
  then refuse both forms or drop this item.

## 4. SSE stable storage, then HTTPClient pooling

* test/ris/sse.ri needs stable storage, then inclusion
  in check.sh: EventParser replaces
  `@line` and `@data` with a new builder in a round, and keeps `@type` and
  `@id_buffer` from `SSE.clean`'s scratch. Give them stable storage.

* HTTPClient pooling: HTTPClient owns one exchange per pooled
  connection with `@idle` as indexes into them, not `{String, Conn}`
  made per request; SSE.open keeps one exchange beside its parser; gate:
  two requests over one connection, `reused` 1. Today `client.open` is
  refused at open_by: the exchange it makes is its own, and give_back
  would keep its Conn in the client. A try (exchanges made in
  initialize, `lend`/`release` by index, `take` given the exchange)
  got past these, in order:
  - `connect_by_records` made and answered a TlsClient and a tuple: it
    takes the exchange, moves the socket into it (an `adopt` beside
    `take_connection`), handshakes on its `tls` slot and answers the
    socket; the caller reads the config back with `https_current`.
  - Exchanges made under `if i <= idle` in initialize (macro-unrolled)
    and pushed into `@exchanges` are refused ("cannot store a view
    beyond its owner scope"). Taking branches out of the checker's
    scopes passes them but breaks refused/root_branch_escape and
    root_store_join: SPEC 3.2 says branch-local storage cannot escape,
    while 1.1 frees only per def, round and block. Decide with EGM, or
    make all MAX_POOLED exchanges (16 resolvers and buffers a client).
  - The resolver refill: read once a request before the loop (done).
  - SvcbStore kept views of the DNS message (done).
  Next: `HTTP.https_endpoints` stores `ech` bytes and the `ordered`
  alpn made in its block into the endpoints, and passes Arrays where
  HttpsEndpoint takes views: build them into caller-owned storage.
  Unknown what follows; the HTTPS-records path never compiled behind a
  client before.

## 5. Tighten heap_trap

* None open: heap_trap checks each case's outcome (ris2).

## 6. Checker `evaluate` stack use

* None open: call_value keeps `evaluate`'s frame small (ris2).

## 7. Benches

* 36 check scripts nothing runs (not CI, not test/ris/check.sh, not another
  script; gates_reachable.py lists them): wire each into CI or delete it.
  test/cli: bounded_gate.sh, collections_exercise.sh, collector_free_floor.sh,
  daemon_agrees.py, debug_info.py, enum_exercise.sh, float_text.sh,
  format_exercise.sh, gates_reachable.py, generic_boundary.py, io_exercise.sh,
  language_is_named.py, lsp_artifacts.py, lsp_positions.py,
  lsp_token_boundaries.py, mod_context.sh, mod_diff.sh, number_exercise.sh,
  packages_get.sh, parallel_exercise.sh, runtime_exercise.sh,
  sandbox_story.sh, server_load.sh, socket_exercise.sh, tarball_std.sh,
  test_verb.sh, value_exercise.sh, verbs_exercise.sh,
  wasm_concurrency_probe.sh, windows_exercise.sh. test/speed: defer_cost.sh,
  definition_typing_scale.py, measured_numbers.py, metric_port.sh,
  rebuild_speed.py, tls_speed.sh.
* test/cli/agent_loop.py fails at step 12 on main (2026-11-10) and no CI
  job runs it (gates_reachable counts it only through a spec comment):
  fix it and put it in .github/workflows/ris.yml. Its `check -f json`
  and `fix --json` calls still need moving to `check types --json`
  (diagnostics in the steps object) and `check types --fix`.
* test/cli/test_verb.sh fails on main (2026-11-10) at "the discount says
  when it turns itself off": the eiy macro gets the file name
  `::String.view(::String.view("page.eiy"))` and panics `cannot read`.
* test/cli/packages_get.sh: 9 FAIL (get/reach/doc/mod context), 31 on main
  before ris check; test/cli/verbs_exercise.sh: a reopen of String (now a
  struct) and `fix printed its edit` (split.iyi already clean).

* Build each test/cli program, group refusals by message, fix per group.
  2026-11-11, minitest: 83 of 139 pass --no-codegen, up from 80.
  The 56 remaining programs are grouped below by their first refusal.
  Final test/ris/check.sh: PASS: all ris checks; zero FAILED lines.
  Runtime, named_tuple and io now pass --no-codegen. Runtime runs to
  `runtime exercise: every property held`; io runs to ALL CHECKS PASSED.
  named_tuple's full driver passes plain/release, mutation and missing-key
  gates. NamedTuple#to_h takes the caller's Hash; clone takes an explicit
  owner. IyiIO#lines takes caller-owned text backing its returned views.
  The io fixture's second Sized now reads its second, unconsumed source.
  The checker remains unchanged.
  Partial API ports remain open at their next refusal; passing a first
  refusal does not count a program as built:
  - API drift, 6: fuzz still has byte-View argument mismatches and the
    removed HTTP parser surface. Its mutator owns writable destinations;
    TLS identities and record ciphers are named at the call sites.
    http2_tape_frames, http2_tape_request and http2_tape_response still
    use private Conn/H2Connection hooks. Decide whether to replace them
    with public HTTP network benches or retire the old comparisons.
    xml's fixture expects the removed full XPath value API, while std
    now documents a subset: restore that coverage or port the fixture
    to the subset. wasm32 tests removed GC APIs (IyiMark, IyiWeak,
    collect and alloc_atomic): replace with tape coverage or retire it.
  - Scratch results, SPEC 1.9, 5: std's tally, png's picture, time's
    read_zoneinfo, yaml's read_value and toml's reads. Hash results need
    caller-owned destinations; compound results need backing storage.
    TOML's generator now uses caller-owned pools and text, and recursive
    canonical/syntax writers append into a builder; its parser wrappers,
    generated tables and derived Hash readers still fail lifetime checks.
  - Round data stored past it, 3: ct_timing, cookie and dir. Keep output
    storage before the round and write into it; copy what is retained.
  - Def data stored past it, 2: socket's cached SocketIO and http_server's
    current multipart Part. Keep backing storage on the receiving owner
    and refill it rather than storing a helper's temporary.
  - Block data stored past it, 9: big, bzip2, eiy, indexable, rsa, slice,
    sse, user and xz. Split reused locals from outer bindings, append to
    stable storage, or copy retained values to their destination owner.
  - Views stored past owners, 4: compress, secure_dns, tar and zstd.
    Keep source/decoder storage with its consumer, or write/copy output
    into a caller-owned destination. secure_dns stops at socket.iyi:4178.
  - TLS/HPKE/upgrade owners, 10: http2, tls, autocert, http_latency,
    http_resume, hpke, http, http_stop, acme and websocket. Declare the
    identity, config, client, HPKE context or Upgraded at its caller.
    ACME and WebSocket's owner factories are ported; both now reach
    HTTP.records_handshake, which returns a new TLS owner (section 4).
  - An owner answered by a def, 1: benchmark's bm, then IPS Entry owners
    kept in an Array. Caller-owned jobs need stable entry storage.
  - Procs outliving their tape, 5: dns, file, file_utils, router and
    http_https_records. Move socket/file creation inside tasks and send
    copied text/config; keep direct callbacks inside their owners.
    HTTPS records now uses DnsLookup/reply destinations, named TLS server
    configs and named encrypted upstreams; its captured UdpSocket is next.
  - Request data on the program tape, 3: log, ocsp and x509. Make retained
    parents, zones and certificates in program-owned storage explicitly.
  - Live views across reset/growth, 2: csv and zip. Finish using each row
    or chunk before refill, or copy retained views. Reduce a suspected
    checker-summary error before changing any checker; none proven here.
  - Opaque callback, 1: iterator's to_a over a map/each_slice-produced
    element. Use a directly known consumer or provide a summary proof;
    do not weaken unknown-effect refusals.
  - In-place constructor growth, 1: netip's PrefixSet(prefixes). Make
    the set first, then add prefixes in a separate method.
  - Growing owner in a runtime Array, 1: p256's private keys. Give each
    key stable storage; collect handles rather than growing owners.
  - Read after its round, 1: process's line. Consume it inside the round
    or append it to the caller's builder.
  - Raw String pointer, 1: tls_probe. Use String/byte APIs; only the
    actual OS handoff belongs in a small annotated std def.
  - Invalid constant, 1: number's FOLDED_SIZE. Reduce constant folding of
    the compound modulo expression; do not replace the tested expression
    by a literal.
  Known failures outside this round: format on main, text's chomp-CR
  assertion, and std_regex's task stack overflow at deepest nesting.
  Known checker hole: shuffled.map { |s| SemanticVersion.parse(s) },
  where shuffled holds views of another Array's Strings, is refused as
  a block result made in scratch (semantic_version maps over indices).
* std_http_exercise's and std_fuzz's parse checks call
  `Server.parse_request`, gone with `Request`: read through
  `Server.parse_head` or a socket round trip. Most of
  std_http_exercise.sh's mutation patterns no longer match http.iyi.

## 8. Speed

Speed work stays out of minitest. The jq check at jqg.ri:424 is the
maintainer's.

At the end of each Now step, run ris-bench's `goose-evals.sh medium`
(the goose-evaluations ports jq, json, ninja and yaml against Goose)
and put one line per port in the step's commit body.
x = ris time / Goose time, median of 5 runs; lower is faster. A
timing is a baseline and never fails a gate; nothing is timed per
change. Gates stay structural.

## 9. Language and runtime

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

## 10. std

* HTTP answer's slow request path still uses String-based read_head and
  body readers. Recheck prefork, TLS and samples/ris/web after it.
* TlsConfig system roots: check whether SystemRoots (00130b97e) already
  keeps them. If still read per handshake, make Certificate copyable to
  Program.tape to keep them once.
* Autocert part B: test/cli/std_autocert_exercise.iyi and its driver, with
  real TLS deadline and parallel-server cases, Pebble, restarts and
  mutation checks (part A's gates: test/ris/autocert.ri, autocert_wire.ri).
* std_process: the `handlers` mutation proof (child keeps this program's
  TERM handler) is not caught.
* Add 128-bit formatting, IDNA and URI resolution.
* src/iyi/float.iyi's parser has a copy in src/iyi/tape.iyi: merge them.

## 11. macOS arm64

SPEC 7.1 lists it; these are what Linux has and it lacks yet.

* Measure pages returned to the OS: scope_frees.ri and fibers/spares.ri read
  /proc, and `MADV_FREE` is lazy, so resident size may not fall. Decide
  between `task_info` with `MADV_FREE_REUSABLE`, or `mmap` over the range.
* Port the other checks in `ris-macos.yml`'s `RIS_CHECK_SKIP`: file_copy_to.ri
  and tls_session_tickets.ri.
* Short frame names in a backtrace, then drop check.sh's `frame_edge`.
* A tarball, its release job and `install_ris.sh`: static LLVM fails there.
* Run a reservation-heavy program on a small Mac: `MAP_NORESERVE` is a no-op.

## 12. Known failures

* Every growing tape value reserves 128 MiB of address space, even a
  128-byte builder (SIDE_RESERVE, region.iyi:529). Under
  `vm.overcommit_memory=2` each is charged: a FileServer answer holds
  up to eight (doc/drafts/fileserver-outgoing.md, Memory).
* compiler_test: 225 failures and two segfaulting groups (Code gen: if,
  Codegen: special vars), each top-level describe run apart (80fc5b354).
* test/cli/concurrency_exercise.sh needs `ulimit -n 8192` and is not in
  check.sh; recheck on minitest.
* test/cli/parallel_exercise.iyi:124 (a task value's Panicked arm) and
  test/speed/metric/metric.iyi (Array of the tape type Planet) do not
  typecheck; recheck on minitest.
* test/cli/std_websocket_exercise.iyi appends to an `io` builder and reads
  it back: move it to a String local, then recheck the artifact
  comparison on minitest.
* test/compiler/iyimod_test.cr's getter/defer case cannot resolve
  `Pointer(RisArrayPool(String))` from boot/shelf's type ids.
* test/cli/socket_exercise.sh: several mutations are not caught; a
  unix-socket mutation fails with "the address is in use". Recheck on
  minitest.
* The mutation phases of std_acme, cookie, router, sse and websocket .sh
  run past 20 minutes; recheck on minitest whether they finish.
* base64's timing ratio fails under load; recheck on minitest.
