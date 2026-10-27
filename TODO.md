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
  RisEvent (TAPE_SPEC 5.2, 5.5, 5.6). The language choices below are the
  target; byte sizing and listed mechanisms still need design and gates.
  * `g.new_actor(T, n, state: S, init: ->(s : S) { }) { |state, msg| }`
    makes RisActor(T), externally a RisWorker. Lower S.new to one named
    worker-local owner, never a stored owner field or returned startup
    value. Init copies captures and cannot wait. Queue sends during init;
    startup panic closes the inbox. Actors: counters, caches, collectors,
    routing. Blocking IO belongs in a task or worker, not a handler.
  * `g.new_inbox(T, n, bytes: ...)` binds receive to its creating task;
    `g.new_worker(T, n) { |inbox| }` binds it to the new worker. Main uses
    its own group. Capacity >= 1; 0 is refused with a hint to request,
    negatives/overflow follow 4.2. No public RisInbox.new. Methods: send,
    <<, receive, receive(ms), request, close, closed?, size, empty?,
    capacity. Worker adds value and done?. Stale operations yield Closed.
  * Send handles are Share regardless of T and preserve runtime identity;
    this never extends a payload borrow. Workers/actors stay on their
    creating task's thread, including creation from a parallel task.
    Message data, including Ary, copies by 1.7; no resources or owners.
    Runtime handles and reply tokens must not traverse record pointers.
  * `RisInbox::Request(M, R)`: w.request(msg, ms), req.message,
    req.reply(value). Resolve exactly one arm for each argument, through
    aliases, overlapping unions and subclasses; suggest distinct tagged
    payloads on ambiguity. Only runtime code constructs envelopes; refuse
    plain send of Request. Payload and reply must both pass copy checks.
    Accepted mail survives requester timeout/cancel; work may take effect.
    Graceful close permits replies; owner death closes unanswered slots.
    A committed reply survives owner death. Expired tokens copy nothing;
    duplicate replies while live panic; stale tokens remain Expired.
  * `g.new_semaphore(n)`: acquire, acquire(ms), release, hold { }.
    Count permits; a cancelled wait consumes none; hold releases on all
    exits. `g.new_event`: fire, wait, wait(ms), fired?. Fire latches and
    broadcasts, including to later waits. Define permit limits, initial
    zero, over-release, fairness and exact wait result types before ports.
    All stale operations yield Closed; waits can yield Cancelled/TimedOut.
    No deadline waits forever, 0 polls, negatives follow 4.2.
  * `g.new_task(owns: client) { ... }`, also new_worker/new_actor, moves
    the resource at start. Check exclusive ownership through aliases and
    holders; creator use after handoff is refused with a hint to work in
    the receiving task or send to it. Define the call/start commit point,
    failed creation, inherited cancellation, cleanup transfer and resources
    never entering the body. Gate deferred closes and captured aliases.
    Task.value never moves and refuses resource results with a hint to
    keep the resource in its worker. Design a checked one-shot take from a
    joined task, with unread-result cleanup,
    repeated/competing takes and surviving-alias refusal, before moving
    socket race results. No fd-as-number escape from resource checks.
  * Normal group block end is runtime work: wait for plain tasks; close
    inboxes in creation order and await each worker/actor drain and finish
    before closing the next; join; discard leftovers and retire records.
    A producer created first can send to a later consumer while draining.
    Earlier programmer close is allowed, never required or proved.
    Early exit cancels children and wakes waits before joining/discarding.
    Owner death discards unread mail immediately and ends pending requests.
    Track task kinds and inbox creation order in group records; define
    task launches during drain, registration after block end and failure
    during normal drain. Nested groups and main need the same protocol.
  * Transactional send/receive/reply: reserve, copy, commit or rollback.
    Wake alone never consumes mail. Waits decide Cancelled, data, Closed,
    TimedOut at the commit point; send ignores cancellation and decides
    Closed before Full. Preserve queued mail on pre-commit copy failure;
    owner death may subsequently discard it. Include reply publication vs
    timeout/death and receive cancellation during copy in one state machine.
    Define the request deadline's start and overflow-safe monotonic math.
    A timeout cannot bound scheduler delay or undo accepted work.
  * Pool design before step 2: task IDs and typed slot/generation handles;
    retire slots on generation wrap, never dereference stale group memory.
    Pins prevent reuse during copies without postponing logical closure.
    Private occupancy metadata exposes no payload views; occupied payloads
    remain valid typed values (6.x). Do not zero an arbitrary union into
    an invalid value. GC roots cover queued/reserved/in-flight payloads,
    replies and task results; clear after commit/discard/rollback, never
    on graceful close. Cover spare mappings and all pool reuse paths.
    Copy ordinary task results and panic data before releasing child tape;
    pending-result helpers preserve borrows and are not message transport.
    Specify lock ordering among scheduler, region registry and collector;
    keep deep-copy work outside the scheduler lock with panic-safe guards.
  * Byte budget algorithm remains open: per-inbox published default,
    queued plus reserved deep-copy storage, splitting aliases. Specify
    alignment, live lengths vs capacities, metadata and stable address
    reservations separately. Preflight overflow and count before mutation;
    Full accepts nothing. Bound reply slots and copy scratch separately;
    reply never yields Full, physical exhaustion remains fatal under 4.2.
    Set numeric defaults and publish accounting before the pool layout gate.
  * Actor lowering needs checked state destinations, field provenance,
    scratch separate from state, and reset after defers on every exit.
    Ordinary local_tape currently refuses outer mutable tape access;
    ordinary scope marks can disable reset. Neither is sufficient as is.
    Preserve copy_to(state)/state writers; reject scratch handles in state,
    including indirect holders. Allow copied completion handles/tokens but
    never a retained state/message borrow in child captures. Define the
    handler's group launch capability without copying IyiGroup records.
    Check blocking effects transitively through cleanup, dispatch, FFI and
    artifact contracts; unknown effects need checked contracts (3.4).
    Parallel actor APIs remain later work.
  * Keep raw data outcomes unambiguous: choose tagged success results or
    refuse payload types overlapping Closed/Cancelled/TimedOut. Settle
    token retention and forwarding for asynchronous replies; never enqueue
    the same Request twice. Static self-request refusal covers proven task
    identity only; runtime checks unknown identity. Name a local call, send
    or another task as the safe form; cross-worker call cycles remain possible.
  Steps, each with a gate:
  2. Settle byte accounting, lifecycle and slot layout first. Build RisInbox
     on typed pools with task records, wait nodes and owner checks together:
     known wrong receiver is a compile error, dynamic misuse a panic with
     the safe form. Scalars inline, Str copied per message. Gate owner
     death, graceful close with mail, copy panic/rollback, cancelled
     receive, concurrent retirement, GC reachability and zero heap under
     --no-gc. Physical exhaustion is a separate fatal-path gate. Reuse the
     local stash "channel tape WIP" only after auditing its release paths:
     close retains mail; committed receive or discard releases it.
  3. Cross-thread handles, generation reuse/wrap and cancellation races;
     gate stale use after group end and no escaped pool payload views.
  4. Timed receive, worker, actor, semaphore, event and request/reply.
     Gate group-end order with a producer before its consumer, main,
     nested groups, early cancel, drain failure and task launches in drain;
     no programmer close or compiler termination proof. Gate expired and
     duplicate replies, ambiguous Request unions, self-request and resource
     move refusal (later use, aliases, captures, defer). Actor gates:
     state outside scratch, reset on every exit, retained destination
     writes, exhaustive message unions, reply only on Request, forbidden
     wait/block with a task/worker hint, panic ends worker. Tape stats:
     growth moves and side transfers read 0.
  5. Port std after its prerequisites: pipe needs receiver-side ownership
     setup, bounded Str chunks/byte credits and credit refunds/wakes on
     close or failure; the current movable reader API needs redesign.
     HTTP slots use a semaphore; accept hands client into a task via owns:,
     permit release in defer survives isolated handler failure. Socket
     race uses an owner inbox of indices and wrapped attempt results to
     avoid sibling cancellation on SocketError; joined one-shot take and
     loser cleanup are prerequisites. Autocert uses tagged worker mail,
     renewal deadlines and per-flight latched events or retained reply
     tokens; preserve broadcast completion and terminal data lifetime.
     Reserve credits/control capacity or use timed stop checks so Full
     cannot lose Stop/Done. An event does not itself wake inbox receive.
  6. Refuse select with tagged receive(ms), semaphore or event hints; port
     bench/tests and samples/workers; remove ris Channel (host Crystal
     Channel stays); review UPSTREAM.md's 930722c entry. Replace g.spawn
     with g.new_task and g.spawn_parallel with g.new_parallel_task, with
     safe-form errors. IyiTask/IyiGroup keep names. Retarget compiler hooks:
     normalizer.cr's iyi_direct_spawn, cleanup_transformer.cr's parallel
     Share boundary and tape_call_graph.cr's name/effect recognition, which
     currently treats send and spawn as suspension. Launch/send must pass
     actor no-wait checks; waits and blocking foreign calls must not.
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
