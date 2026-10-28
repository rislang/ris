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

Order, fastest with fewest tokens: one Sol low run per item, fixes
resumed in the same session, one full check per item, all in this
checkout. Pipe/socket race need poller work for several IO waits at
once; Channel stays for them until then.

* Finish the HTTP prefork port: the server, std, samples and bench
  exercises are ported; fix the websocket failures listed
  under Known failure, then remove this item. A task-owned Conn
  must not grow its buffer inside a nested tape block: TLS/HTTP/2
  connections stay program-owned until growth has an owner-level path.
* Enforce Share-or-copy task captures, local and parallel, through captured
  receivers, handlers and reached state; keep all resources in their
  opening task. Gate: mutable/resource captures refused with safe forms,
  independent config copies, retained results copied to multiple readers.
* Port pipe to one-task OS IO on the poller: nonblocking reads/writes,
  partial-write buffers, EOF-after-drain, EPIPE and cancellation. Settle
  the old piece-count capacity API versus OS byte capacity. Gate: full
  pipe progress, partial IO, reader/writer close, cancel and pipe tests.
* Port socket race to one task with multiple in-flight OS connects and
  poller interests, next-launch/deadline timers and Windows completion
  records. Gate: staggered attempts, early failure/winner, timeout/cancel,
  all losing sockets closed and existing race tests on supported targets.
* Port autocert flights to retained task results for completion broadcast.
  Timed nonconsuming task waits are available as IyiTask#wait(ms); one
  handshake timeout must not cancel shared work. Keep manager/cache state
  in one task serving copied board messages, or independently per task;
  isolate protocols and route replies without stealing other waiters' mail.
  Replace wake/halt/select with tagged control messages or local OS wakes.
  Gate: many waiters, independent deadlines, renewal/stop, manager isolation,
  panic/cancel/result lifetime and existing autocert tests.
  Part A is begun on branch autocert-wip (577035543, does not compile:
  std/autocert.iyi:637 interpolates a Str to the heap); rebase it on
  no-gc and continue from there.
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
* bench/std_websocket_exercise.sh: the bare-socket copy refuses
  @[TaskClosureUnsafe] at std/http.iyi:1787, and x86_64-windows-msvc
  rejects Str in File.extname.
* The mutation phases of std_acme, cookie, router, sse and websocket
  .sh run past 20 minutes; check whether they finish at all.

## Windows (on hold: not worked on now)

* Windows file metadata: move native wide-path conversion and auxiliary
  stat buffers onto tape, then gate Str metadata under --no-gc there.
  POSIX metadata and missing-file errors pass the zero-heap gate.
