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

* Build board core from reusable inbox slabs/free lists, not owner/drain
  hooks: canonical specialized keys across modules, alias identity, union
  wrappers, multi-taker waits/claims, recursive struct/Str codecs, copy
  rollback, linearized count limits and cancellation/data/timeout commit.
  Give registry, waiters, messages and results GC roots or no-GC storage;
  publish physical limits. Gate: FIFO, unique parallel delivery, lowered
  limits racing posts, partial-copy panic/cancel, timed/poll cancellation,
  queued Nil, nested copies/enums, task/group survival, GC stress, zero
  heap and --no-gc link audit. Isolate tests with fresh nominal types;
  use fresh processes to test initially unlimited queues.
* Enforce Share-or-copy task captures, local and parallel, through captured
  receivers, handlers and reached state; keep all resources in their
  opening task. Gate: mutable/resource captures refused with safe forms,
  independent config copies, retained results copied to multiple readers.
* Port HTTP to N tasks, each opening a SO_REUSEPORT listener on the same
  port and accepting/serving its own connections. Task count is the
  connection limit; no permits/semaphore. Copy config and handlers per
  task; keep IdleConns local. Define shutdown and unsupported-platform
  refusal. Gate: simultaneous listeners, N-connection bound, keepalive/TLS,
  panic/cancel cleanup and existing HTTP tests without resource transfers.
* Port pipe to one-task OS IO on the poller: nonblocking reads/writes,
  partial-write buffers, EOF-after-drain, EPIPE and cancellation. Settle
  the old piece-count capacity API versus OS byte capacity. Gate: full
  pipe progress, partial IO, reader/writer close, cancel and pipe tests.
* Port socket race to one task with multiple in-flight OS connects and
  poller interests, next-launch/deadline timers and Windows completion
  records. Gate: staggered attempts, early failure/winner, timeout/cancel,
  all losing sockets closed and existing race tests on supported targets.
* Port autocert flights to retained task results for completion broadcast.
  Add timed nonconsuming task waits: value has no timed wait yet; one
  handshake timeout must not cancel shared work. Keep manager/cache state
  in one task serving copied board messages, or independently per task;
  isolate protocols and route replies without stealing other waiters' mail.
  Replace wake/halt/select with tagged control messages or local OS wakes.
  Gate: many waiters, independent deadlines, renewal/stop, manager isolation,
  panic/cancel/result lifetime and existing autocert tests.
* Port samples/workers to nominal Job/Result, in-band Job quit variants,
  checked post results and explicit cancellation handling. Gate: expected
  results, bounded refusal without spinning, accepted quits and clean join.
* Remove RisInbox, RisWorker, RisSemaphore, RisEvent, request/reply,
  new_task/new_worker, owns:, task.take and ordered drain code, compiler
  checks and obsolete tests after ports pass. Gate: no remaining users,
  replacement diagnostics, full check, std tests and --no-gc.
* Remove Channel/select after all replacement gates pass. Gate: no
  remaining users, full check, std/samples tests and --no-gc link audit.

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
  views, no pointers, so it is flat and copied whole like Tre. Replace
  the four linear-scan TapeMap copies in std/yaml.iyi, toml.iyi,
  xml.iyi and mail.iyi. Start from src/iyi/hash.iyi (the same compact
  layout on Pointers): swap them for Ary; take Crystal's linear scan for
  small maps and index width by capacity. Name it after Str and Ary (Hsh
  or Map). Gate: O(1) lookup on a large map, insertion order, zero heap.

## Known failure to recheck

* Reproduce spec/compiler/iyimod_spec.cr's "carries the constants a
  module's own code reads": runtime constants appear in the constant
  list. Determine whether the artifact or the expectation is wrong;
  make tape-independent fixes in iyi first, or record them in UPSTREAM.md.
* `make compiler_spec` does not build: src/compiler/iyi/command/
  migrate.cr:2065 calls rchop on String | Nil (seen 2026-10-27, before
  and after the inbox work). Compiler specs cannot run until it does.
* bench/concurrency_exercise.sh fails with "pipe2 failed" after its
  32,000 sleepers test (seen 2026-10-27 before the group-end change).

## Windows (on hold: not worked on now)

* Windows file metadata: move native wide-path conversion and auxiliary
  stat buffers onto tape, then gate Str metadata under --no-gc there.
  POSIX metadata and missing-file errors pass the zero-heap gate.
