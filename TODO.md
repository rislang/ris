# ris TODO

Rules: TAPE_SPEC.md. Goal: no GC or general heap, including the runtime.
Measure: test/ris/heap_budget.txt, semantic gates and binary link audits.

How to work (fewer tokens, faster to the goal):

* Demand first: take the largest heap site in an existing workload.
  For an uncovered language guarantee, add a small representative gate.
  Move storage to tape or typed pools; lower changed budget rows in the
  same commit. Unrelated module migrations wait.
* One change, one relevant gate: check the promised behavior, including
  error paths the census cannot see. Zero counted allocations alone do
  not prove runtime exemptions or repeated use are heap-free.
* Replace, don't wrap: when a String API has a tape twin, grep the repo
  for callers. Few: move them to the tape API and delete the String API
  in one commit. Many: keep the wrapper for now.
* TODO holds open work only, one item per task; completed work lives in
  git log. Remove an item when its guarantee passes its gate, not merely
  when a sample's budget reaches zero.

## Estimates (2026-10-28, rough)

Codex Sol low tokens; review adds 10-30%. Done 2026-10-28: no GC is the
only mode; program literals, to_s, prints, closures and task values are
on the tape, with the core String/Array/Hash API. Before testing ris programs:
the std row. Update a row when its work starts or ends.

| Work                                  | Size     | Time      | Tokens    |
|---------------------------------------|----------|-----------|-----------|
| std heap: 119 mallocs, 13 non-compiling | large    | 2-3 days  | 300k-800k |
| Text: `s = ""` + `<<`, no Builder.new | medium   | 6-10 h    | 300-500k  |
| Kernel threads without a collector    | large    | 1-2 days  | 300-500k  |
| Task value: @[OnTape] and nested      | medium   | 2-4 h     | 100-200k  |
| Closure env inside a nested tape do   | medium   | 2-4 h     | 100-200k  |
| 5.1 std_* bench ports: verify no GC   | medium   | 2-4 h     | 150-300k  |
| 5.1 holes: reached state, aliases     | large    | 4-8 h     | 200-400k  |
| Autocert part B                       | medium   | 2-4 h     | 150-300k  |
| Task-owned Conn buffer growth         | med-lrg  | 3-5 h     | 150-300k  |
| Artifact String constructor contract  | small    | 1-2 h     | 50-100k   |
| Compiler specs: the rest of the suite | large    | 1-3 days  | 300k-1M   |
| macOS arm64 (needs a Mac to test)     | medium   | 1-2 days  | 200-400k  |
| Windows                               | large    | days      | 500k+     |

## Messages: RisBoard (TAPE_SPEC 5.2, 5.6; doc/MESSAGES.md)

All work in this checkout, one full check per item; Codex is out of
usage until 2026-11-02. Pipe is an OS pipe on Linux and macOS (refused
elsewhere). Done: HTTP/2 1 MiB POST, websocket bare copy, autocert part
A, OS pipe, socket race without Channel, 5.1 local task captures,
Channel and select removed. Next in order: bench ports, then autocert
part B.

* Give a task-owned Conn an owner-level buffer growth path: growth in a
  nested tape block ends with the block, so TLS/HTTP/2 connections stay
  program-owned (one buffer per connection never freed) until then.
* Port the benches to 5.1 task captures. Done: std_signal (exercise
  passes; a listener stops by its task handle's `cancel`, the Share stop
  handle), std_process's captures (ChildProcess#read_both, task values,
  Atomic). concurrency and stdin_park typecheck. std_term and runtime
  pass; std/process's buffers and tables are on the caller's tape, ENV's
  on program storage. std_process passes but for one mutation proof:
  `handlers` (child keeps this program's TERM handler) is not caught.
  http_latency/resume/stop captures are ported (per-task configs, task
  values, HTTPClient `tls:`). First refusals left:
  - captures: tls (ech_pair, crafted, faked, captured pass caller
    TlsServerConfig/TlsConfig into a server task: needs a Copyable or
    Share config, or one server task per section as binding_server),
    udp:274 (UdpSocket shared by a receive task and the caller), dns:951
    (server task and client share `log`, sockets), mutex (bench
    deleted with Mutex, 2026-10-29). sse and websocket captures are
    ported: HTTP.open and SSE.open yield their block, an upgrade's
    takeover reads its 101, one task owns a WebSocket (the two-sender
    tests are gone: 5.1 refuses sharing one). Left: http.iyi:2154
    (serve's `handle`) and sse.iyi:513 (`Response.stream`'s block):
    opaque callback effects, for the narrower opaque proc contract;
    sse.iyi:543 (Hash shrink while copying headers per reconnect);
    std/compress is on tape Arrays (no Pointer); std_compress's bench
    stops at `Inflater.new { feed.next }` (an opaque source proc).
  - not captures: http_latency, http_resume, http_stop check in 64-79 s
    (the program checker reuses walks by input structure); they stop at
    the shrink refusal http_continue has (below). HTTP.tls_config= is
    gone (refused, naming HTTPClient.new(tls:)); acme, http2_exercise
    and std_http_exercise.sh's inline programs still call it. TlsConfig
    reads the system roots per handshake: make Certificate copyable to
    Program.tape to keep them once again.
    socket, file, http, json import std/gc; yaml: Array(Any) refused (growing
    values): retire Any for TapeValue; server_load: IyiMark (collector
    gone; the bench proves collections, drop or rewrite it).
* 5.1 left: receivers and state reached through called methods (only the
  block's own captures are checked), aliases of a handed-off value.
* Port socket race to one task with multiple in-flight OS connects and
  poller interests, next-launch/deadline timers and Windows completion
  records. It no longer uses Channel/select: the caller polls its attempt
  tasks (2 ms slices), and the attempts still write a shared outcome
  array. Gate: staggered attempts, early failure/winner, timeout/cancel,
  all losing sockets closed and existing race tests on supported targets.
* Port autocert to one manager with copied board orders and cached results.
  Part A implements Copyable config, task-local views, tagged stop,
  independent cache-poll deadlines, failure broadcast and expiry, renewal
  reload and process-wide manager isolation. Flights own protocol sessions
  under the manager's group; no mutable client crosses task boundaries.
  Gates: test/ris/autocert.ri and autocert_wire.ri, registered in check.sh.
  Part B remains: finish bench/std_autocert_exercise.iyi and its driver,
  including real TLS deadline/parallel-server cases, Pebble, restarts and
  mutation checks. Preserve the policy probe's copied board observations;
  its Counter is no longer captured by the listener task.

## Text: `s = ""` and `<<`, no Builder.new (user decision 2026-10-29)

One text type and one way to append; the compiler decides where text
grows. `String::Builder` stays only as a parameter type ("append to the
caller's text"). Change TAPE_SPEC 7.3 in the step that implements it.

```crystal
out = "Viga: "          # a view of the literal, no cost
out << code << '\n'     # first << reserves and copies the literal once
@data << value          # a field grows in its own reservation, too
greet(out)              # def greet(io : String::Builder): out grows
@data = ""              # reuses the reservation if no view outlives it
```

In order, one gate each (RIS_TAPE_STATS: 0 moves, 0 copies after the
first):

* Done: `a = []`, `h = {}` and `Hash.new(0)` infer from the first store
  in .ri files (test/ris/array_infer.ri); `Hash.new(0)` is a Hash(K, V)
  carrying its default, so a `Hash(K, V)` parameter takes it. std
  (.iyi) still needs `[] of T`.
* Done: appended locals and fields grow (test/ris/text_grow.ri); a
  field declared or started as a non-String type (`@x : Array(T)`,
  `@x = [] of T`) gets no text companion (text_field_kinds.ri).
* Done: a reset (`s = ""`, `@data = x`) reuses the reservation when
  the shrink checker's text pass proves no old view is live, else it
  refuses naming `copy_to(owner)` (test/ris/text_grow.ri, ten
  test/ris/refused/text_reset_* cases with a mutation check).
* Done: `<<` on a String parameter in a program is refused, naming
  `io : String::Builder` (test/ris/text_param.ri, refused/
  text_param_append.ri). The copying `s + x` fallback no longer runs
  for program locals and fields: every appended one grows (step 1).
* Done: a String local started from text and assigned once is lent to a
  `String::Builder` parameter (`text = ""; greet(text)`) and rebound to
  its text after the call; `s << a << b` appends every link to `s`.
  Others are refused naming that form (test/ris/text_param.ri,
  refused/text_lend_*). std (.iyi) does not lend yet.
* Crystal code to ris through `ris fix`: each common refusal carries a
  `suggested_edit` that fix applies. Done: a plain `String::Builder.new`
  -> `""`, then its `x.finish` -> `x.to_s`, plain `String.build` blocks
  (a multi-line edit), and an `IO` text parameter -> `String::Builder`
  (test/ris/fix/). Left: a new Array per call -> `clear`. Gate per rule: a
  Crystal-style file that `ris fix` turns into one that compiles, and
  fix leaves alone what it cannot prove.
* Done: in programs, a String::Builder local or String.build argument
  that only appends (`<<`) and is read back (`finish`, `to_s`) is
  refused, naming `text = ""` (test/ris/refused/text_plain_build*.ri,
  text_builder_kept.ri). A builder with byte methods, passed to a call
  or unused stays legal: an overload on String (`join(separator)`)
  would take the text silently. 19 test and sample files moved.
* std (.iyi) builders: lend and the refusal apply to .ri programs only.
  Extend both to src/std with the std port, then move its ~320 plain
  builders. test/ and src/iyi/ keep their literal capacities.

## std port (session state: tape_state.txt; group one, then group two)

* Done: std/aead and the tls record layer hold no tape pointer and no
  malloc. aead uses checked bulk copies into its cipher's local blocks
  (bench/std_aead_exercise.sh holds); tls keeps its inbox and outbox as
  fixed Arrays that std/socket reads and writes in place, and seals
  records through aead's Array `seal_at`/`open_at`. On this machine,
  aead improved from 40/41/56 to 92/81/162 MB/s for AES-128-GCM,
  AES-256-GCM and ChaCha20-Poly1305 (2026-10-29). Left: tls's
  `read(Pointer, count)` stays, marked, for std/http's Conn buffer;
  bench/std_tls_exercise waits on the 5.1 bench port (its server task
  captures a tape config).
* Then, as tape_state.txt orders them: log, sse,
  http, websocket, cookie, router; group two smallest first.

## Next

* Escaping closures outside program and joined task owners: pooled
  environments, including captured receivers; release them with their
  owner, check capture lifetimes and refuse unsupported escapes safely.
* Finish typed pool validation (TAPE_SPEC 6.1-6.4): audit remaining bounds,
  overflow, membership, stale views, reset lifetimes and external images.
  Borrowed Run constructors now retain Array shrink lifetimes; gates cover
  constructor bounds and foreign Array storage as well as pool storage.
* For FFI paths in use, enforce borrow lifetimes, retained-storage owners,
  foreign-thread attachment and no unwind across foreign frames.

## Remove the heap and switch off the GC

* Runtime pools (test/ris/task_reuse.ri): fibers, task and group slots
  and defer nodes are reused. Left: a long-lived group (a server's) or
  an `IyiGroup.new` keeps each task's slot until it ends; parallel task
  fibers are not pooled; a spawned block's captured closure data still
  takes program storage per spawn.
* samples/ris/logline.ri runs (18 mappings for 1,000,000 lines):
  EntryWriter's tape block is proved and reset per line. The heap gate
  checks every heap_budget.txt row again.
* std's target, as Goose does it (doc/reference/goose/docs/design/
  owning_dynamic_data.md): short-lived String/Array/Hash on the caller's
  tape; long-lived state (HPACK tables, autocert cache, log sinks) in
  typed Pool/SlicePool with explicit free and index links. Until then the
  no-GC malloc is the old bump allocator with the trap off: std works but
  never frees, so a long-running server leaks (RIS_HEAP_STATS=1 shows
  it). Remove the bump allocator and restore the trap when std is moved.
* A program def's closure environment is on its current tape (codegen
  closure_owner 1). A spawn with captures inside a `local_tape` block
  into a group opened outside it is refused (task_local_tape); a nested
  `tape do` shares the outer tape; a call inside a `local_tape` to a def
  that (transitively) spawns with captures into a group it was handed is
  refused (task_local_tape_helper). Left: a spawn reached through a
  proc call, which the check cannot follow. std keeps its marks.
* Error#message answers String, which a program cannot build without a
  heap: let it answer String (or write into a builder) across std.
* Kernel threads without a collector on darwin arm64 and win32: Linux
  has them (spawn_parallel uses every core); the others still need the
  collector's stop to build thread.iyi.
* Remove general allocator fallbacks from ris programs. Distinguish
  gc_none's allocator behavior from ris_no_gc's allocation trap; audit
  remaining std and runtime paths required by supported workloads.
* Audit final program binaries for collector linkage and forbidden heap
  allocator dependencies; keep the compiler's own GC choice separate.
* Autocert's program objects: pool them behind generation-checked
  handles, as pipe ends are (Std::Io::RisPipeEnd, pipe_reuse).
* HTTP answer's slow request path still uses String-based read_head and
  body readers. Migrate those before claiming chunked/Expect/HTTP/1.0
  answer parity without a heap. Recheck prefork, TLS and samples/ris/web.
* Finish mixed String/tape migration fixtures and no-GC logging gates.
* Remove remaining obsolete collector paths in ris programs.

## Later

* Finish ordinary class tape allocation for HTTP migration classes:
  migrate TlsStream connection/body holders. Opting these holders in
  reaches joined server captures and opaque streamed-body callbacks;
  establish checked lifetime contracts before enabling these paths.
  Unmarked runtime and std declarations still use the migration allocation
  ABI; selected std classes opt in with @[OnTape].
* Complete the Pool/SlicePool surface beyond the validated paths in use.
* std heap left (2026-10-30 audit): 102 Pointer.malloc/realloc sites,
  133 to_heap copies. Ports in compress style (tape Arrays): bzip2 33,
  xz 16, png 5, deque 4, string_pool 4, csv 3, password 4. Done:
  websocket reader and regex (gates websocket_reader, regex*). OS
  buffers left are win32 or sized: file 8, user 6,
  process 5, system 4, dir/path/socket/udp 2 each. to_heap stores into
  plain classes: time 25, autocert 17, toml 13, xml 12, yaml 11.
  Not compiling under ris: csv ini toml yaml xml
  udp mail smtp png zip tar xz netip otp debug (gc by design).
* Sweep remaining std modules (collections, IO, errors); heap paths that
  block the default no-GC switch belong in the section above.
* Add 128-bit formatting, IDNA and URI resolution.
* Leave the scope mark off a def, loop or block that puts nothing on the
  tape (`ror32`, a loop of arithmetic): its check runs each call and round.
  Draft, not built or measured: branch idea/pure-scope-marks (0ae15fb23,
  tape_scope_checker.cr). Do it when speed is measured again.
* Extend RIS_TAPE_STATS with owner paths and pool waste.
* Stable growth on every supported tape target: replace moving backends
  outside Linux with address-space reservations and equivalent gates.
* A tape hash map, laid out as Ruby's Hash (st_table): entries in an Array
  in insertion order, bins an Array(Int32) of indices into it, String keys as
  views; links are indices, so it is Copyable and packed like RisTree. Replace
  the four linear-scan TapeMap copies in std/yaml.iyi, toml.iyi,
  xml.iyi and mail.iyi. Start from src/iyi/hash.iyi (the same compact
  layout on Pointers): swap them for Array; take Crystal's linear scan for
  small maps and index width by capacity. Name it after String and Array (Hash
  or Map). Gate: O(1) lookup on a large map, insertion order, zero heap.

## Known failure to recheck

* check.sh triage (2026-10-29, two full runs on minitest agree; all
  deterministic, none load or temp-path races; fail at 5a375faec too):
  * Tape stats: fixed. Stdio buffers went to Program.tape (program_scope),
    a mapping of their own; now program storage (storage_scope). A task
    panic copied its text through a scratch work queue; now one String.
    owner_construction_panic gates 302 scopes, 7 mappings: each panic's
    text is kept in a result region until the group ends.
    query_scope: fixed, 7 mappings. Query.decoded's String.build was a
    def's fresh result, staged in a pending region and copied back;
    Query.parse now makes each decoded string at its size in place.
  * text_default: fixed in the test. The loop kept no tape; the
    `"key".to_heap` before it copies onto the tape, so `before` is read
    again after it.
  * call_contracts: fixed. A proc literal's parameter took the slot of
    an outer growing text local of the same name (normalizer); a local
    proc of a non-tape type lost its literal (shrink checker).
  * index_view: fixed; tape_indexable's copying values_at(Array(Int32))
    overrode the view.
  * copy_rollback: fixed in the test. Array(String) copies bytes into its
    own string pool, never through String#__iyi_copy_into; 1.7 promises
    the rollback, not the hook. A struct leaf now injects the failure.
  * slice_pool: fixed. Array growth uses __relocate_slice; links are
    refused where a run joins a pool (nested Array, test nested_links).
    flat.ri: fixed; the shrink checker no longer counts Array::Link
    as a view.
  * pointer_unsafe and ffi_marked: done. An @[Ffi] module passes
    `text.to_unsafe` straight to a lib fun; elsewhere it stays refused
    (pointer_unsafe_to_unsafe, ffi_to_unsafe_stored).
  * interpolation_retained and contract_spawn: done, now runs gates
    (TAPE_SPEC 1.6); task_local_tape(_helper) cover the unsafe cases.
  * autocert lifecycle and wire: fixed. AcmeJson.each_object yields
    each object in place (no Array of Hash); ACME answers are @[OnTape];
    AcmeClient#finalize is finalize_order (a class may not finalize).
    The manager reads certificates with AutocertView#read, not load,
    and keeps no view of its Hashes across a grow or delete; a flight
    writes its failure inside its group, while the message lives.
  * log_metadata, log_tape: pass again (log.iyi:279 no longer stops
    them). samples/ris/orders and request: fixed; they called the
    one-argument Server.parse_head, which answers RequestHead, and
    JSON.parse; now parse_head(bytes, 0, true) and JSON.document.
  * answer, server_owners, http_continue: pass. std/zstd is on tape
    Arrays (no Pointer, malloc or to_unsafe), as std/compress is.
* growing_owner: fixed; an owner held in an Array or RisTree (also a
  SlicePool's @data) gets the container refusal.
* Server programs (answer, server_groups, web, server_owners, serve,
  http_prefork) pass the shrink checker in about 75 s; request builds.
  Fixed: a callee field mapped onto a base whose type lacks it (a
  String) is dropped, not folded (conn.fill); a branch ending in
  `return` bounds its shrinks; an If with one leaving branch guards
  what follows; Host replaced while filling the table (:2627); H2
  flush clears after the write. The to_unsafe rule's stops in
  compress.iyi and zstd.iyi are gone; http_prefork, serve,
  logline and the heap gate pass. TAPE_SPEC 3.2 is a compiler
  rule now (TapeShrinkChecker): data made in an explicit `tape` block,
  stored where it outlives it (a local, field or object from outside,
  also through calls), is refused naming copy_to; tests refused/
  tape_block_store_call, tape_block_handler_store, tape_block_reset.
  A block TapeShrinkChecker proves (no opaque keep, no lazy text growth
  of an outer String, no call storing what it made into an outer
  object) gets its scope mark, so each request's scratch is freed.
  The fast path called the one-argument parse_head and never ran; it
  takes parse_head(bytes, 0, false) now. The one-argument
  Server.parse_head is refused, naming parse_head(bytes, 0, true)
  (refused/http_parse_head_text); the server's own RequestHead reader
  is the private request_head. server_groups makes 48
  mappings, bounded (50 at 9x the requests); its gate is 64 (was 29,
  set before every Array took a side reservation). A copy into an
  Array's own pool, or copy_to into
  an outer object's method, keeps the block's tape (shows no contents).
* tls.iyi:5257: done. TlsServerConfig#identity_source is a
  TlsIdentitySource (a trait: identity_for(server_name, alpn,
  left_ms)); AutocertView implements it; a proc is refused, naming the
  trait. x509, rsa, p256 and ecdsa are off to_unsafe and malloc
  (p256's and ecdsa's base tables on Program.tape); handshake_secret
  split in two (an always-nil PSK reached codegen as a bare Nil).
  std_tls_exercise now stops at its own line 585, https_records at a
  proc over a UdpSocket (366), autocert_exercise at the Array(Hash)
  refusal. Done before: the takeover
  is the handler's take_over(socket, leftover, response), called after
  Response.upgrade(headers)'s 101; a block passed to Response.upgrade or
  WebSocket.upgrade is refused, naming the new form; WebSocket.serve
  runs the connection; Server.coded adds Accept-Encoding to Vary as it
  copies; the source is handed a copy of the ALPN offer.
* Compiler specs (run with LLVM_CONFIG set to LLVM 23; without it
  bin/crystal links the system LLVM 21). Green (2026-10-30):
  compiler_spec, iyimod, proc, closure, macro_methods. Fixed then: the
  closure check's raise needs an alloca block (String is a struct); an
  artifact numbering a file-private runtime type (RisArrayPool) resolves
  it from the runtime files; a foreign-name type keeps @[OnTape]; a
  constant read back already lowered to `__ris_program_init` is the
  compiler's. iyimod "carries the constants": the artifact is right, its
  code reads runtime constants (STDERR, ARGC_UNSAFE, ...) too.
  Pending: iyimod "carries an owning type's Share marker": a class is a
  tape value, so the tape-capture rule refuses Guard(Counter) before the
  Share gate; the artifact Share refusal has no spec that reaches it.
  Left, across the suite (one file per process, 8 at a time): 58
  failures, 427 errors in 93 files; def, if, special_vars, iyi_import,
  tools/init and loader/msvc print no summary. Main causes: "General
  allocation is unavailable" (79), Crystal's "prelude" requires (78), a
  String result read without the prelude (40), missing exception types.
* bench/concurrency_exercise.sh passes every step under `ulimit -n 8192`
  (the 2,000 idle pipes need it). Its failure proofs copy the runtime to
  <dir>/src/iyi/: the compiler knows runtime files by that path. Recheck
  it after runtime changes; it is not in check.sh.
* Typecheck failures that predate the Channel removal:
  bench/parallel_exercise.iyi:124 (a task value's Panicked arm) and
  bench/metric/metric.iyi (Array of the tape type Planet).
* x86_64-windows-msvc does not typecheck std/socket.iyi:572
  (connect_named: opaque callback effects); fix with the socket race.
* bench/std_websocket_exercise.sh's artifact comparison stops in the
  source build: bench/std_websocket_exercise.iyi uses an `io` builder
  that only appends and is read back. Migrate it to a String local, then
  recheck the comparison. Constructor String fields now keep the receiver
  store in their artifact contract (test/ris/iyimod_tape.py).
* The artifact getter/defer case in spec/compiler/iyimod_spec.cr cannot
  resolve `Pointer(RisArrayPool(String))` from boot/shelf's type ids
  (seen 2026-10-29); recheck after the constructor contract fix.
* bench/socket_exercise.sh ends "something above failed": several
  mutations are not caught and a unix-socket mutation fails with "the
  address is in use". Race checks pass; compare with 05b93f1e2.
* The mutation phases of std_acme, cookie, router, sse and websocket
  .sh run past 20 minutes; check whether they finish at all.

## Windows (on hold: not worked on now)

* Windows file metadata: move native wide-path conversion and auxiliary
  stat buffers onto tape, then gate zero-heap String metadata there.
  POSIX metadata and missing-file errors pass the zero-heap gate.
