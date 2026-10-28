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
* Drop the dead Channel leftovers in src/iyi/concurrency.iyi: IyiWaiter,
  spare_waiter, IyiFiberState::WaitingCh's channel comments and the
  channel/select notes in the scheduler's comments.

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

* Audit runtime allocations hidden by RisHeap.runtime_depth; migrate the
  remaining sites, then remove counting and --no-gc enforcement exemptions.
* Remove general allocator fallbacks from ris programs. Distinguish
  gc_none's allocator behavior from ris_no_gc's allocation trap; audit
  remaining std and runtime paths required by supported workloads.
* Define supported no-GC targets and gate each one; unsupported targets
  must fail explicitly rather than silently select a heap fallback.
* Audit final program binaries for collector linkage and forbidden heap
  allocator dependencies; keep the compiler's own GC choice separate.
* Make no-GC behavior the default after the semantic, runtime, workload
  and link gates pass; remove obsolete collector paths in ris programs.

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
  bench/parallel_exercise.iyi:124 (a task value's Panicked arm),
  bench/thread_exercise.iyi:286 (tape type Rendezvous in a proc) and
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
  stat buffers onto tape, then gate Str metadata under --no-gc there.
  POSIX metadata and missing-file errors pass the zero-heap gate.
