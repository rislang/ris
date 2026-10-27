# Messages between tasks: design

How ris replaces iyi's Channel with RisActor, RisInbox, RisWorker,
RisSemaphore and RisEvent. The rules are TAPE_SPEC 5.2, 5.5 and 5.6;
this file holds the mechanisms and gates the steps in TODO.md build.
Names may change once the model works.

## 1. API and names

* `g.new_inbox(T, n, bytes: ...)` binds receive to its creating task;
  `g.new_worker(T, n) { |inbox| }` binds it to the new worker. Main uses
  its own group. Capacity >= 1; 0 is refused with a hint to request,
  negatives/overflow follow 4.2. No public RisInbox.new. Methods: send,
  <<, receive, receive(ms), request, close, closed?, size, empty?,
  capacity. Worker adds value, take and done?. Stale operations yield Closed.
* `g.new_actor(T, n, state: S, init: ->(s : S) { }) { |state, msg| }`
  makes RisActor(T), externally a RisWorker. Lower S.new to one named
  worker-local owner, never a stored owner field or returned startup
  value. Init copies captures and cannot wait. Queue sends during init;
  startup panic closes the inbox. Actors: counters, caches, collectors,
  routing. Blocking IO belongs in a task or worker, not a handler.
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
  duplicate committed replies while live panic; stale tokens are Expired.
  request(..., reply_bytes:) supplies a positive budget, default 64 KiB,
  charged to the requester-side slot, not inbox bytes. Oversize reply is
  Full before any copy; leave the slot open and requester waiting so a
  smaller value can retry. Expired beats Full; check liveness again at
  commit. Physical exhaustion follows 4.2, never a reply-budget failure.
* `g.new_semaphore(n)`: initial = maximum n >= 1. FIFO live waiters,
  no newcomer bypass; over-release panics. Pre-acquire n to start empty.
  acquire/acquire(ms) and event wait/wait(ms): Nil | Cancelled | TimedOut;
  release/fire: Nil; fired?: Bool; all add Closed after group end.
  hold releases only after successful acquire and on every exit.
  Event fire is idempotent, latched and broadcast to later waiters too.
  No deadline waits forever, 0 polls, negatives follow 4.2. Implement
  wake without permit consumption; cancellation removes the waiter and
  wakes its successor. Gate FIFO, no barging, over-release, pre-acquired
  empty credits, cancelled wake, hold unwind and stale observations.

## 2. Storage: pools, byte accounting, transactions

* Pool design before step 1: task IDs and typed slot/generation handles;
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
* Generate one sizing/copy plan: root inline slot once, each destination
  allocation's payload plus allocation header rounded to 8 bytes. Count
  Ary live length * sizeof(element), its state, Builder live bytes/state,
  Tre live Entry storage and concrete class instances. Walk only extra
  backing allocations after counting inline fields, not inline fields
  twice. Split aliases and stop preflight as soon as over budget; no user
  callbacks. Source data must remain stable through preflight and copy.
  Default inbox bytes = max(64 KiB, capacity * 4 KiB), positive override;
  checked arithmetic before mutation. Count queued and reserved copies;
  rollback releases reservations. Exclude unused address reservation,
  page slack, pool metadata and scratch; publish separate finite runtime
  limits for these costs. bytes: is not an RSS cap. Reply sizing uses the
  same plan with request reply_bytes, default 64 KiB, outside inbox bytes.
  A Full reply copies nothing and preserves the live slot for retry;
  Full never delivers a reply or resets the request deadline. Physical
  exhaustion remains fatal under 4.2. Gate empty containers, headers,
  classes, unions, split aliases, compact capacity, aligned accounting,
  budget overflow, concurrent reservations and rollback, oversized reply
  then smaller success, Full vs expiry, timeout after Full and no copy on
  Full/Expired. Publish limits/accounting before the pool layout gate.
* Transactional send/receive/reply: reserve, copy, commit or rollback.
  Wake alone never consumes mail. Waits decide Cancelled, data, Closed,
  TimedOut at the commit point; send ignores cancellation and decides
  Closed before Full. Preserve queued mail on pre-commit copy failure;
  owner death may subsequently discard it. Include reply publication vs
  timeout/death and receive cancellation during copy in one state machine.
  Define the request deadline's start and overflow-safe monotonic math.
  A timeout cannot bound scheduler delay or undo accepted work.

### Implemented scalar and Str slice (2026-10-27)

`g.new_inbox(T, n, bytes: ...)` now creates a task-owned handle for
concrete integer and float scalars, Bool, Char, Symbol, Nil, enums and Str.
Other payloads name scalar or Str inboxes as the supported form. Channel
and std remain unchanged. This first slice had no receive deadline; the
timed entry point is settled below. Unknown receiver identity is checked
at runtime. Static receiver checking remains open.

The runtime maps typed pools of 4,096 inbox records and 65,536 message
records per process, allocated from free lists. Intrusive owner and group
chains make retirement visit only their own inboxes. Pinned retired slots
return to the free list after the last copy. One wait node per inbox
keeps a waiting owner alive through the scheduler registry.
Handles contain a slot and 64-bit generation. Retirement invalidates the
handle, and generation wrap permanently retires its slot. Owner death
and group end discard mail and retire records; graceful close retains
mail. Ordered worker drain was added by the step 5.3 slice below.

Scalars occupy inline message storage. Str bytes use reusable mapped
slabs with power-of-two classes from 32 bytes through 1 MiB, including
the header. Each slab is at least 64 KiB. Committed receive or discard
returns the block to its class. Larger allocations map and unmap directly.
Accounting is `round8(sizeof(T))` plus, for Str,
`round8(16 + bytesize)`; 16 is the allocation header size. Empty Str still
costs its header. The default budget is `max(65536, capacity * 4096)`;
explicit budgets must be positive.
Count and byte reservations include in-flight copies. A copy runs outside
the scheduler lock, pins its record, and publishes or rolls back under
that lock. Cancellation after a receive copy preserves queued mail.
Unwind guards return reservations and pins before owner-death cleanup.

Excluded storage has finite limits: the two fixed metadata pools above,
one wait node per inbox, and cached slabs retained for process lifetime.
Slabs grow with peak simultaneous demand in each class; there is no
separate cache cap. Str length is at most 2,147,483,647 bytes. Above the
1 MiB allocation threshold each live Str has a page-rounded mapping.
Receive copies use the caller's existing tape limits and spare-mapping
policy. Physical pool or mapping exhaustion is fatal, distinct from an
inbox's Full budget.
Fatal-exhaustion gates remain for later steps. The gates below extend
reuse, stale-handle and copy-rollback coverage across threads.
The storage gate sends and receives 100,000 small texts after warm-up;
`__ris_inbox_storage_maps` counts message-storage mmap calls and must
stay unchanged. `__ris_inbox_owner_touches` counts owner-death record
visits; 10,000 tasks without inboxes must add zero with another inbox
live. Both gates run under `--no-gc` and assert zero heap allocations.

### Cross-thread handles and cancellation (step 5.2, 2026-10-27)

The owning Share annotation on RisInbox already accepts handles for every
supported scalar and Str payload at spawn_parallel's capture boundary.
No compiler exemption was needed. inbox_parallel instantiates each scalar
kind, enums and Str; a separate refusal keeps an unrelated Array capture
non-Share beside the inbox handle. Passing a handle extends no Str borrow.
The Str gate retains a received value while recycled message storage is
overwritten and checks that the retained bytes do not change.

All pool initialization, record/message free-list operations, slab mapping,
slab free-list operations and retirement run under IyiSchedLock. Only a
pinned copy's private bytes are accessed outside that lock. Owner-death
hooks in normal return, panic and cancellation, and group-end cleanup,
hold the same lock. Inbox wake uses IyiScheduler.ready: a foreign-thread
wake posts to the owner's home scheduler and rings its poller. It never
moves the owner onto the sender's scheduler. Gates cover owners created
on the main scheduler and on a parallel worker.

A receive must read its message's following link at commit under the lock.
The old pre-copy snapshot could miss an append during the unlocked copy,
losing queued mail. The runtime now reloads that link. inbox_parallel runs
four parallel senders with 1,000 messages each, repeated 20 times, checking
exact counts and each sender's order at the owner. inbox_races forces an
append while receive is pinned and verifies both deliveries exactly once.

inbox_reuse checks every method, including << and observations, on handles
from group end and owner death across 10,000 subsequent slot reuses. The
ris_inbox_test build flag enables a near-wrap generation hook, identity
inspection and locked pin/message/release counters. These are absent from
ordinary builds. inbox_wrap starts at UInt64::MAX - 2, checks the final
reusable generation, then verifies that 10,000 allocations never reuse
the retired slot. Stale generations stay Closed throughout.

inbox_races repeats three forced cancellation interleavings 100 times:
owner death while another thread holds a send reservation; cancellation
of an owner parked in receive followed by a foreign-thread publication;
and cancellation while a worker owner's receive copy is pinned. Send
ignores cancellation while the owner lives. Receive cancellation consumes
nothing. Owner death defers physical discard until pins are released.
The gates check retained mail before death, zero pins and live messages
after cleanup, and exactly one release for every message. Instrumented
release also refuses a double release. Pause hooks run outside the lock.

inbox_reuse and inbox_wrap run under --no-gc with zero heap allocations.
The parallel and race gates run on the normal threaded runtime with four
workers. The runtime explicitly refuses spawn_parallel under --no-gc
(and gc_boehm); check.sh gates that refusal rather than claiming no-GC
parallel coverage. The step 5.3 slice below adds deadlines and workers.
Richer payloads, actors, static receiver checks and physical exhaustion
remain later steps.

### Timed receive and ordered workers (step 5.3, 2026-10-27)

`receive(ms : Int32)` now starts one monotonic deadline at entry. Zero
polls; a negative size panics with the safe forms `receive(0)` to poll
and plain `receive` to wait. The millisecond conversion fits Int64 and
the deadline addition saturates rather than overflowing. Plain receive
keeps its deadline-free result type. `TimedOut` implements Error with
message "timed out". A timed call adds TimedOut to T, Closed and Cancelled.

The scheduler lock protects the decision: Cancelled before queued data,
then Closed, then TimedOut. A copied message commits under that same lock;
a deadline expiring during the copy does not beat available data. Cancel
before commit preserves the queued message. A parked timed receive uses
the owner's sleep heap and removes its deadline when it resumes, whether
woken by data, close, cancellation or timeout. Wakes consume no message.
The inbox nonce still prevents a stale wake from waking an unrelated wait.

`g.new_worker(T, n, bytes: ...) { |inbox| ... }` creates a local task and
its task-owned inbox in one locked registration. The worker receives its
inbox directly; a caller gets send, <<, close, closed?, size, empty?,
capacity, value and done?. The public `RisWorker(T)` interface is a
module, implemented by the value handle `RisWorkerTask(T, R)`. R preserves
the block's result type through IyiTask without adding a heap wrapper or
boxing the result. The handle is owning Share, just like RisInbox; it
copies identity and grants no receive access. It extends no payload borrow.
The compiler treats the handle as runtime identity, so a Str payload
parameter is not mistaken for a captured Str borrow. Workers created by
parallel tasks stay on their creating scheduler.

Group inbox records now append at the tail in creation order. Normal
join waits for all live plain tasks, closes the oldest remaining inbox,
and waits for its worker to finish before advancing. Owner death removes
its records under the scheduler lock. Closing an ordinary inbox after the
plain barrier advances the cursor but retains its unread mail until all
children join; final group cleanup then discards it and retires the record.
Plain tasks created during drain are awaited again before advancing, and
newly created inboxes append to the tail. Returning a failure during
drain immediately cancels siblings; explicit cancellation and early
block exit do the same. All
these paths wake waiters, join children, discard leftovers and retire.

A task's body reports failure immediately, but its live count and child
list entry remain until its tape cleanup and owner-death cleanup finish.
The final Done transition, count change and barrier wake share the lock.
This prevents a foreign scheduler from advancing a barrier while a task
is still cleaning up. Panics retain their existing delivery policy.

Registration and sealing use that same scheduler lock. A task's adoption
is its registration commit, before enqueue; worker adoption and inbox
allocation commit together. Preparation before adoption publishes no work
to the group, so it needs no separate reservation. A draining group seals
only when its inbox chain is exhausted and its live count is zero. A
registration either commits before that seal and is joined, or panics:
"the group has ended; create this work in a live outer group". The old
unlocked ended check is gone from both task launch paths. Cancelled groups
still accept already-cancelled plain tasks; inbox and worker creation are
refused with a live-group hint.

The new gates in check.sh cover these decisions:

* inbox_timed: zero poll, elapsed monotonic timeout, timed data/close wakes,
  data before Closed/TimedOut, Closed before TimedOut, and cancellation
  before queued data without consumption. Data/close wakes remove timers.
* inbox_negative: a negative timeout panics and names both safe forms.
* inbox_worker: round trip, inbox observations, typed result, done? and
  stale inbox closure after worker death.
* inbox_drain: automatic closure without programmer close, producer before
  consumer, plain descendants at the first barrier, and workers and plain
  tasks registered while a worker drains, and unread main-owned mail
  retained through graceful close until the final join.
* inbox_early: timed wait cancellation, cancellation during drain, returned
  failure during drain, and an early break which joins cancelled workers.
* inbox_sealed: ended groups refuse task, inbox and worker registration
  with the exact safe-form panic.
* inbox_worker_parallel: owning Share scalar/Str worker captures and scheduler
  affinity for workers created on both main and parallel schedulers.
* inbox_registration: 100 concurrent local/parallel task and worker
  registration attempts
  versus sealing; accepted work finishes before group end, refused work
  never runs.

The timed, worker, drain, early, negative and sealed gates require zero
reported heap allocations under --no-gc. Threaded gates use four workers.
inbox_races now alternates
plain and zero-timeout receive in its pinned-copy cancellation gate.
Existing group/task gates remain part of the full check.

Request/reply, owns:, task.take and RisActor remain open in step 5.3.
This slice does not extend supported payloads, resource transfer, actor
scratch or static receiver checking.

### Semaphore and event (step 5.3, 2026-10-27)

`g.new_semaphore(n)` now supplies initial and maximum permits n >= 1.
Zero and negative counts panic with the pre-acquire safe form: make a
positive semaphore, then acquire its permits to start empty. acquire and
acquire(ms) return Nil, Cancelled, TimedOut or RisInbox::Closed. release
returns Nil or Closed and panics when all maximum permits are available.
Permit accounting commits under the scheduler lock, after cancellation
and handle validation. Waking a task never consumes a permit.

Each semaphore has a FIFO of parked tasks. A newcomer cannot acquire
while that queue is nonempty, including when the head has been readied
but has not committed. Cancellation removes its waiter without taking a
permit and wakes the successor if a permit is available. Timeout also
unlinks the waiter. Queue links live in the runtime's typed task records;
each task can have only one active blocking call. Removing a waiter is
constant work, with no scan of tasks or pool slots.

hold runs its block only after successful acquisition, returns the
block's answer and releases through defer on every exit, including panic.
The deferred call captures slot and generation scalars rather than
boxing the handle receiver. Failed acquisition returns its status and
never installs a release.

`g.new_event` supplies wait, wait(ms), fire and fired?. fire latches the
event and readies every present waiter. Later waits succeed immediately;
repeated fire is harmless. Group cancellation wakes parked waits with
Cancelled. Both timed APIs use one monotonic deadline, saturating the
addition; zero polls and negative milliseconds panic with poll and
unbounded-wait safe forms. Available data wins over timeout, while
cancellation wins before a live acquisition commits.

Both handles are owning Share values containing only slot and generation.
Their records share a scheduler-locked mmap-backed typed pool with 4096
slots and a chain owned by each group. Pool exhaustion is fatal with a
hint to reduce live synchronization objects. Group end retires that
chain, advances generations
and returns slots to the free list. Generation wrap permanently retires a
slot. Stale operations return RisInbox::Closed before inspecting task
cancellation. Reusing this existing status keeps one Closed case across
inboxes, semaphores and events, without adding a duplicate status type.
No stale operation dereferences a stored group pointer. Compiler checks
refuse direct pool access and forged handles with group-factory hints.

The ordered plain-task barrier now reads a live plain-task counter.
Adoption increments it and completion decrements it under the scheduler
lock; workers are excluded at adoption. Normal return, panic and stopped
cancelled tasks all use the completion path. Each barrier decision is
constant work rather than walking the remaining children after every
completion. Final panic reporting and cancellation may still walk once.

New check.sh gates:

* sync_basic: pre-acquired empty start, acquire timeout, hold result and
  release, event poll/timeout, 100-waiter broadcast and later latched wait.
* sync_fifo: ordered acquisition, no barging after waking the queue head,
  cancellation between wake and commit, successor wake, preserved permit,
  timeout removal and event cancellation on group cancel.
* sync_lifecycle: stale operations after slot reuse, closed hold skips its
  block, hold release during panic, over-release panic, invalid counts and
  safe-form hints.
* sync_linear: 10,000 plain tasks plus an inbox worker, with exact live
  counter assertions before release and after group end. This is a
  structural linearity gate: the barrier uses only the counter; it does
  not impose a machine-dependent timing bound.
* sync_parallel: owning Share handles, timed waits and contended permits
  across four worker schedulers.
* sync_forge: direct handle construction through the runtime factory is
  refused with group-factory hints.

The four single-thread executable gates require zero reported heap
allocations under --no-gc. Request/reply, owns:, task.take and RisActor
are later slices.

## 3. Lifecycle: group end and resources

* Normal group block end is runtime work: wait for plain tasks; close
  inboxes in creation order and await each worker/actor drain and finish
  before closing the next; join; discard leftovers and retire records.
  A producer created first can send to a later consumer while draining.
  Earlier programmer close is allowed, never required or proved.
  Early exit cancels children and wakes waits before joining/discarding.
  Owner death discards unread mail immediately and ends pending requests.
  Track task kinds and inbox creation order in group records. Members
  and their descendants may register during drain: append new inboxes to
  the tail, never reopen closed entries; await all live plain tasks at
  each next-inbox barrier, repeating if new tasks appear. Under the
  scheduler lock, seal only with an exhausted closing cursor, no live
  children and no in-flight registration reservation. Validation and
  registration must use that same protocol; the old unlocked @ended
  check before adopt is insufficient. After sealing, new_* panics:
  "the group has ended; create this work in a live outer group".
  Failure during drain switches to cancelling and bypasses ordered drain;
  new tasks inherit cancel, new inbox/worker/actor creation is refused.
  Nested groups and main use the same protocol. Order is guaranteed, not
  termination: a plain task awaiting a later worker's shutdown or endless
  worker creation can prevent group end. Gate finite tail creation,
  grandchildren, registration vs sealing and cancellation during drain.
* `g.new_task(owns: client) { ... }`, also new_worker/new_actor, moves
  the resource at start. Check exclusive ownership through aliases and
  holders; creator use after handoff is refused with a hint to work in
  the receiving task or send to it. Define the call/start commit point,
  failed creation, inherited cancellation, cleanup transfer and resources
  never entering the body. Gate deferred closes and captured aliases.
  Task.value refuses resource results with a hint to task.take. Result
  return consumes child ownership into a group-owned typed slot before
  child defers/tape release: disarm/transfer close obligations, exclude
  surviving aliases and stage copyable tape fields. take joins and pins
  the result while staging caller-owned copies; rollback leaves the slot
  unclaimed. Only group owner can commit Unclaimed -> Claimed and move
  resources; cleanup responsibility changes atomically at that point.
  Cancel before claim consumes nothing; a second live take panics, stale
  handles yield Closed; keep value's panic-delivery behavior. Retain
  unclaimed results independently of the live-child list. Group cleanup
  claims/closes resource fields once on normal or early exit; cleanup
  panic follows 4.1. Gate mixed resource/tape results, deferred close,
  aliases, double take, cancel/copy panic before claim, no take, stale
  take and child panic. No fd-as-number escape from resource checks.

## 4. Actor lowering and compiler checks

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
* Keep plain outcome unions: refuse top-level T/R alternatives
  overlapping Closed/Cancelled/TimedOut/Full/Expired, including bare
  control types, aliases and broad base types such as Error. Suggest a
  distinct wrapper struct; do not ban control values in its fields or
  Request's already-wrapped M. Check after specialization and dispatch;
  gate bare types, alias/union/base overlap and accepted wrapper fields.
  Settle token retention/forwarding for asynchronous replies; never enqueue
  the same Request twice. Static self-request refusal covers proven task
  identity only; runtime checks unknown identity. Name a local call, send
  or another task as the safe form; cross-worker call cycles remain possible.

## 5. Steps and their gates

TODO.md lists one item per step; each is done when its gate passes.

1. Implement accounting/lifecycle and gate slot layout first. Build RisInbox
   on typed pools with task records, wait nodes and owner checks together:
   known wrong receiver is a compile error, dynamic misuse a panic with
   the safe form. Scalars inline, Str copied per message. Gate owner
   death, graceful close with mail, copy panic/rollback, cancelled
   receive, concurrent retirement, GC reachability and zero heap under
   --no-gc. Physical exhaustion is a separate fatal-path gate. Reuse the
   local stash "channel tape WIP" only after auditing its release paths:
   close retains mail; committed receive or discard releases it.
2. Cross-thread handles, generation reuse/wrap and cancellation races;
   gate stale use after group end and no escaped pool payload views.
3. Timed receive, worker, actor, semaphore, event and request/reply.
   Gate group-end order with a producer before its consumer, main,
   nested groups, early cancel, drain failure and task launches in drain;
   no programmer close or compiler termination proof. Gate expired and
   duplicate replies, reply Full/retry/timeout, ambiguous Request unions,
   control-type collisions, self-request and resource move refusal (later
   use, aliases, captures, defer), one-shot take and unclaimed cleanup.
   Actor gates:
   state outside scratch, reset on every exit, retained destination
   writes, exhaustive message unions, reply only on Request, forbidden
   wait/block with a task/worker hint, panic ends worker. Tape stats:
   growth moves and side transfers read 0.
4. Port std after its prerequisites: pipe needs receiver-side ownership
   setup, bounded Str chunks/byte credits and credit refunds/wakes on
   close or failure; the current movable reader API needs redesign.
   HTTP slots use a semaphore; accept hands client into a task via owns:,
   permit release in defer survives isolated handler failure. Socket
   race uses an owner inbox of indices and wrapped attempt results to
   avoid sibling cancellation on SocketError. Take the winner inside the
   group, cancel/join losers and let group cleanup close unclaimed
   successes; completion indices must also cover attempt panic. Autocert
   uses tagged worker mail, renewal deadlines and per-flight latched
   events or retained reply
   tokens; preserve broadcast completion and terminal data lifetime.
   Reserve credits/control capacity or use timed stop checks so Full
   cannot lose Stop/Done. An event does not itself wake inbox receive.
5. Refuse select with tagged receive(ms), semaphore or event hints; port
   bench/tests and samples/workers; remove ris Channel (host Crystal
   Channel stays); review UPSTREAM.md's 930722c entry. Replace g.spawn
   with g.new_task and g.spawn_parallel with g.new_parallel_task, with
   safe-form errors. IyiTask/IyiGroup keep names. Retarget compiler hooks:
   normalizer.cr's iyi_direct_spawn, cleanup_transformer.cr's parallel
   Share boundary and tape_call_graph.cr's name/effect recognition, which
   currently treats send and spawn as suspension. Launch/send must pass
   actor no-wait checks; waits and blocking foreign calls must not.
