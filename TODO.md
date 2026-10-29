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
| std paths that still use the heap     | large    | 1-3 days  | 300k-1M   |
| Text: `s = ""` + `<<`, no Builder.new | medium   | 6-10 h    | 300-500k  |
| Kernel threads without a collector    | large    | 1-2 days  | 300-500k  |
| Task value: @[OnTape] and nested      | medium   | 2-4 h     | 100-200k  |
| Closure env inside a nested tape do   | medium   | 2-4 h     | 100-200k  |
| 5.1 std_* bench ports: verify no GC   | medium   | 2-4 h     | 150-300k  |
| 5.1 holes: reached state, aliases     | large    | 4-8 h     | 200-400k  |
| Autocert part B                       | medium   | 2-4 h     | 150-300k  |
| Task-owned Conn buffer growth         | med-lrg  | 3-5 h     | 150-300k  |
| Artifact String constructor contract  | small    | 1-2 h     | 50-100k   |
| Compiler specs signal 11              | unknown  | 2 h-1 day | 100-300k  |
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
    (server task and client share `log`, sockets), mutex (a tape Mutex
    in a joined task: needs a rule for Share(owns) tape types), sse
    (std/sse.iyi:546 parser), websocket (std/websocket.iyi:380 chosen).
  - not captures: http_latency, http_resume, http_stop stop at
    std/http.iyi:6052 (`@failure = got`, program-tape store); socket,
    file, http, json import std/gc; yaml: Array(Any) refused (growing
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
* Then, as tape_state.txt orders them: log, autocert's nested Hash, sse,
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
* std/uri: URI.parse of a String, then normalize.to_s, answers
  "//@:80/a/c?q#f": the fields are lost (test/ris/uri_legacy.ri, out of
  check.sh). Parsing a String works. Fix the String path or drop it.
* std's target, as Goose does it (doc/reference/goose/docs/design/
  owning_dynamic_data.md): short-lived String/Array/Hash on the caller's
  tape; long-lived state (HPACK tables, autocert cache, log sinks) in
  typed Pool/SlicePool with explicit free and index links. Until then the
  no-GC malloc is the old bump allocator with the trap off: std works but
  never frees, so a long-running server leaks (RIS_HEAP_STATS=1 shows
  it). Remove the bump allocator and restore the trap when std is moved.
* A program def's closure environment is on its current tape (codegen
  closure_owner 1): a task spawned inside a nested `tape do` that ends
  before the task reads freed captures. Allocate it at the group's or
  the def's scope, or refuse the spawn there. std keeps its marks.
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
* Finish check.sh under the sole no-GC mode. Seven left: autocert
  lifecycle, hpack, http_continue, answer, http_prefork,
  time_tape_offset (std String paths) and side_spares (5 mappings
  made where the gate expects 4; fails at a6015b397 too).
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
* Sweep remaining std modules (collections, IO, errors); heap paths that
  block the default no-GC switch belong in the section above.
* Add 128-bit formatting, IDNA and URI resolution.
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

* growing_owner refuses with the field rule, not the container one.
* samples/ris/web.ri does not build: std/http.iyi:2627
  (`headers[host_name] = named`) is refused as a Hash shrink with a live
  view, after about 7 minutes of checking (seen 2026-10-29 on the base).
* No check.sh block hangs any more: the shrink checker settles and the
  server programs check in 2-37 s (server_groups, answer and web 37 s;
  profile the program checker next). They now stop at std refusals the
  hang hid: http.iyi:6052 (`@failure = got` in the http2 writer's
  flush, "cannot store request tape data on the program tape") and
  log.iyi:362 (`initialize(@io : IO, ...)`, the same); and
  http_continue.ri imports `Conn`, which std/http does not export.
* Compiler specs (run with LLVM_CONFIG set to LLVM 23; without it
  bin/crystal links the system LLVM 21): no signal 11 any more. Left:
  compiler_spec lines 484, 522, 568 use Channel and select (port to
  RisBoard or mark pending; the build error exits the process, so no
  summary); proc (16 of 19 errors) and closure (5) `require "prelude"`,
  Crystal's, which ris does not offer (switch the helper to ris's
  prelude or mark pending); macro_methods: 7 stale heap-String
  expectations, 2 has_inner_pointers?, 2 read_file examples whose String
  has no fields (also codegen/class_var_spec.cr:292); iyimod: 3
  failures, 19 errors (IyiThread x2, Str::Builder, `<<` for
  RisTextGrowth from an artifact, App::Stack#push).
* Reproduce spec/compiler/iyimod_spec.cr's "carries the constants a
  module's own code reads": runtime constants appear in the constant
  list. Determine whether the artifact or the expectation is wrong;
  make tape-independent fixes in iyi first, or record them in UPSTREAM.md.
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
