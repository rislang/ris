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
on the tape, with the core Str/Ary/Hsh API. Before testing ris programs:
the std row. Update a row when its work starts or ends.

| Work                                  | Size     | Time      | Tokens    |
|---------------------------------------|----------|-----------|-----------|
| std paths that still use the heap     | large    | 1-3 days  | 300k-1M   |
| Kernel threads without a collector    | large    | 1-2 days  | 300-500k  |
| Task value: @[OnTape] and nested      | medium   | 2-4 h     | 100-200k  |
| Closure env inside a nested tape do   | medium   | 2-4 h     | 100-200k  |
| 5.1 std_* bench ports: verify no GC   | medium   | 2-4 h     | 150-300k  |
| 5.1 holes: reached state, aliases     | large    | 4-8 h     | 200-400k  |
| Autocert part B                       | medium   | 2-4 h     | 150-300k  |
| Task-owned Conn buffer growth         | med-lrg  | 3-5 h     | 150-300k  |
| .iyimod keeps @[OnTape]               | small    | 1-2 h     | 50-100k   |
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
* Port the benches to 5.1 task captures: the compiler now refuses a local
  task's non-Share capture unless handed off. First refusals in
  collect_trigger, concurrency, runtime, server_load, socket, stdin_park,
  and std_ dns, file, http, http_latency, http_resume, http_stop, json,
  mutex, process, signal, sse, term, tls, udp, websocket, yaml. Shared
  locals become task values or board messages; a listener stopped from
  another task needs a Share stop handle (design it, do not mark it).
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

## Next

* Escaping closures outside program and joined task owners: pooled
  environments, including captured receivers; release them with their
  owner, check capture lifetimes and refuse unsupported escapes safely.
* Finish typed pool validation (TAPE_SPEC 6.1-6.4): audit remaining bounds,
  overflow, membership, stale views, reset lifetimes and external images.
  Borrowed Run constructors now retain Ary shrink lifetimes; gates cover
  constructor bounds and foreign Ary storage as well as pool storage.
* For FFI paths in use, enforce borrow lifetimes, retained-storage owners,
  foreign-thread attachment and no unwind across foreign frames.

## Remove the heap and switch off the GC

* std/uri: URI.parse of a String, then normalize.to_s, answers
  "//@:80/a/c?q#f": the fields are lost (test/ris/uri_legacy.ri, out of
  check.sh). Parsing a Str works. Fix the String path or drop it.
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
* A task's tape value is copied into a group result region and onto the
  reader's tape for Str, Ary, Hsh, Tre and tuples of them; @[OnTape]
  structs and nested containers are still refused.
* Error#message answers String, which a program cannot build without a
  heap: let it answer Str (or write into a builder) across std.
* Kernel threads and spawn_parallel without a collector: thread.iyi and
  the parallel pool are gated on !gc_none, so ris programs have no
  IyiThread and run every task on one core. Split the stop-the-world
  collector parts from the thread code; restore program_readers,
  program_threads and program_field_thread (test/ris/check.sh).
* Remove general allocator fallbacks from ris programs. Distinguish
  gc_none's allocator behavior from ris_no_gc's allocation trap; audit
  remaining std and runtime paths required by supported workloads.
* Audit final program binaries for collector linkage and forbidden heap
  allocator dependencies; keep the compiler's own GC choice separate.
* Finish check.sh under the sole no-GC mode. Seven left: autocert
  lifecycle, hpack, http_continue, answer, http_prefork,
  time_tape_offset (std String paths) and fibers/spares (memory).
* Pipe ends are program objects (56 bytes each, kept until exit) and
  IyiIO#read_str answers tape text. Replace with generation-checked
  typed pool handles so a closed pipe's end is reused; autocert next.
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
* A tape hash map, laid out as Ruby's Hash (st_table): entries in an Ary
  in insertion order, bins an Ary(Int32) of indices into it, Str keys as
  views; links are indices, so it is Copyable and packed like Tre. Replace
  the four linear-scan TapeMap copies in std/yaml.iyi, toml.iyi,
  xml.iyi and mail.iyi. Start from src/iyi/hash.iyi (the same compact
  layout on Pointers): swap them for Ary; take Crystal's linear scan for
  small maps and index width by capacity. Name it after Str and Ary (Hsh
  or Map). Gate: O(1) lookup on a large map, insertion order, zero heap.

## Known failure to recheck

* Compiler specs (seed 71173, 2026-10-27): recheck macro/macro_methods,
  iyimod, compiler, and codegen/{proc,closure}_spec.cr; four failures and
  two errors preceded a signal 11 crash in the closure group, so no
  failure summary was printed.
* Reproduce spec/compiler/iyimod_spec.cr's "carries the constants a
  module's own code reads": runtime constants appear in the constant
  list. Determine whether the artifact or the expectation is wrong;
  make tape-independent fixes in iyi first, or record them in UPSTREAM.md.
* bench/concurrency_exercise.sh fails with "pipe2 failed" after its
  32,000 sleepers test (seen 2026-10-27 before the group-end change).
* Typecheck failures that predate the Channel removal:
  bench/parallel_exercise.iyi:124 (a task value's Panicked arm) and
  bench/metric/metric.iyi (Array of the tape type Planet).
* x86_64-windows-msvc does not typecheck std/socket.iyi:572
  (connect_named: opaque callback effects); fix with the socket race.
* .iyimod artifacts drop @[OnTape] on types: a build from std artifacts
  refuses File::Info's Str fields (bench/std_websocket_exercise.sh,
  "does not run the same from its artifacts").
* bench/socket_exercise.sh ends "something above failed": several
  mutations are not caught and a unix-socket mutation fails with "the
  address is in use". Race checks pass; compare with 05b93f1e2.
* The mutation phases of std_acme, cookie, router, sse and websocket
  .sh run past 20 minutes; check whether they finish at all.

## Windows (on hold: not worked on now)

* Windows file metadata: move native wide-path conversion and auxiliary
  stat buffers onto tape, then gate zero-heap Str metadata there.
  POSIX metadata and missing-file errors pass the zero-heap gate.
