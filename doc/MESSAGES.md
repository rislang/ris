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
