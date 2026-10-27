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

## Workload blockers (goose-evaluations, 2026-10-26)

* jq under --no-gc runs 5-13x slower than Goose: find the cause once
  the ports run; speed tests otherwise stay off.

## Remaining tape semantics

* Stable growth on every supported tape target: replace moving backends
  outside Linux with address-space reservations and equivalent gates.
* Escaping closures outside program and joined task owners: pooled
  environments, including captured receivers; release them with their
  owner, check capture lifetimes and refuse unsupported escapes safely.
* Finish typed pool validation (TAPE_SPEC 6.1-6.4): audit remaining bounds,
  overflow, membership, stale views, reset lifetimes and external images.
  Borrowed Run constructors now retain Ary shrink lifetimes; gates cover
  constructor bounds and foreign Ary storage as well as pool storage.
* Replace Channel with RisActor, RisInbox, RisWorker, RisSemaphore and
  RisEvent (TAPE_SPEC 5.2, 5.5). Names (may change once the model works):
  * `g.new_actor(T, n, state: S, init: ->(s : S) { }) { |state, msg| }`
    makes a `RisActor(T)` (TAPE_SPEC 5.5, 5.6), the
    main tool: the compiler writes the loop, the handler borrows state
    built in place in the worker and handles one message on scratch.
    Outside it is a RisWorker. Actors: counters, caches, collectors,
    routing. Workers: http accept, socket race, pipe, autocert. Tasks:
    paired fetches, CPU work; a logger that writes IO is a task or a
    worker, an actor only queues lines.
  * `g.new_inbox(T, n)` makes a `RisInbox(T)` owned by the calling task,
    not the group; `RisInbox.new` is not public, so every inbox ends
    with a group. Main makes them in its own `group do |g|`. `send` and
    `<<`, `receive`, `receive(ms)` (0 does not wait), `close`,
    `closed?`, `size`, `empty?`, `capacity`. Not push/pop: Ary#pop
    takes the last element.
  * `g.new_worker(T, n) { |inbox| }` makes a `RisWorker(T)`: a task
    owning a RisInbox(T), which the block receives from. The worker
    has `send`, `<<`, `request`, `close`, `closed?` (to its inbox),
    `value` and `done?` (as IyiTask). Share, like the send handle.
  * `RisInbox::Request(M, R)`: `w.request(msg, ms)`, `req.message`,
    `req.reply(value)`; a one-shot reply slot with a token, so a late
    reply answers `RisInbox::Expired`, a second one panics and a reply
    is never Full. R comes from the inbox's Request variant for M; two
    variants for one M are a compile error. One inbox
    takes requests and plain messages as a union:
    `RisInbox(Str | RisInbox::Request(Str, Int32))`.
  * `g.new_semaphore(n)`: `RisSemaphore` with `acquire`, `acquire(ms)`,
    `release`, `hold { }`. `g.new_event`: `RisEvent` with `fire`, `wait`,
    `wait(ms)`, `fired?`. Their waiters get Cancelled at the group's end.
  * Errors: `RisInbox::Full`, `RisInbox::Closed`, `TimedOut`,
    `Cancelled`. Send never answers Cancelled: it does not wait.
  * No select: a task waiting on several sources takes them through
    one inbox with tagged messages (a union), as Erlang does, and waits
    with receive(ms).
  The contract is TAPE_SPEC 5.2, 5.5 and 5.6 (settled 2026-10-27). A
  message is what copy_to accepts, so Ary is not refused. The socket
  race moves its winner as the joined attempt's result. Parallel
  actors are later work.
  Steps, each with a gate (design review of 2026-10-27):
  2. RisInbox on typed pools, with task records and wait nodes: scalars
     inline, Str copies per message, close, group end, rollback;
     preserve queued messages on pool failures and prove zero heap
     under --no-gc. Take from the Str channel work (local git stash
     "channel tape WIP"): copy on receive, release on close, failed
     receives keep mail.
  3. Owner checks (compile error, runtime refusal) and cross-thread
     send handles for parallel tasks.
  4. receive(ms), RisWorker, RisActor, RisSemaphore, RisEvent,
     request/reply; gate dead owner, expired reply, self-request and
     group end with queued mail (Koja MEMORY-MODEL.md, Process
     boundaries). RisActor release gates: state outside scratch, reset
     on every exit, copy_to(state) and state writers kept, a scratch
     handle stored in state refused, waits and blocking calls in a
     handler refused with a hint to a task or a worker, exhaustive
     message unions, reply only on a Request, panic ends the worker;
     RIS_TAPE_STATS growth moves and side transfers read 0.
  5. Port std: pipe (semaphore credits), http slots (semaphore),
     socket race (inbox), autocert (one inbox of tagged messages and
     an event), samples/workers.
  6. Refuse select with a hint to receive(ms) and tagged messages;
     port bench and tests (host Crystal Channel stays); remove Channel;
     review the 930722c entry in UPSTREAM.md. In the same pass free ris
     of spawn: g.spawn becomes
     g.new_task, g.spawn_parallel g.new_parallel_task, and a spawn in
     ris code is refused with a hint to them. The name says what you
     get, as Ruby's Thread.new does. IyiTask and IyiGroup keep their
     names: they do not change. The compiler matches the names:
     the group join in normalizer.cr (iyi_direct_spawn) and the Share
     check on a parallel block must follow, with error texts. About
     600 uses, most in bench/; spec/ and the host compiler keep
     Crystal's spawn.
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

## Known failure to recheck

* Reproduce spec/compiler/iyimod_spec.cr's "carries the constants a
  module's own code reads": runtime constants appear in the constant
  list. Determine whether the artifact or the expectation is wrong;
  make tape-independent fixes in iyi first, or record them in UPSTREAM.md.

## Windows (on hold: not worked on now)

* Windows file metadata: move native wide-path conversion and auxiliary
  stat buffers onto tape, then gate Str metadata under --no-gc there.
  POSIX metadata and missing-file errors pass the zero-heap gate.
