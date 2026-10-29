# TAPE_SPEC.md changelog

Every change to TAPE_SPEC.md gets an entry here in the same commit: date,
what changed and why. Newest first. An agent never edits the spec without
one.

## 2026-10-29: Tre is RisTree

* Changed: 1.2, 1.4, 1.7, 5.6, 7.2 name the tree type RisTree; its
  layout and rules are unchanged.
* Why: AGENTS.md names a type iyi does not have Ris*. Moving it to std
  over Array was tried and refused: an Array field is a pool run that
  may move as it grows (7.5), and the JSON parser reads a tree while it
  grows; the tree's own reservation never moves, so it stays a core type.

## 2026-10-29: a builder that only appends is refused

* Changed: 7.3. In a program, a String::Builder local or String.build
  argument used only with `<<`, `finish` and `to_s` is a compile error
  naming `text = ""`; one passed to a call or used for bytes stays.
* Why: the user's decision. One way to build text; a String local grows
  in place, so the builder adds a type and two steps for nothing.

## 2026-10-29: an appended String grows in its own reservation

* Changed: 7.3. A String local or field that gets `<<` owns a growing
  reservation from its first append (one copy of the start text);
  before, `<<` extended in place only at the tape's cursor and otherwise
  copied all of the text, so a field or a busy local grew in O(n^2).
* Why: the user's decision. `s = ""` and `<<` replace String::Builder
  in ordinary code (TODO "Text"); that is only sound if it never copies.

## 2026-10-28: String, Array, Hash and Tre are the tape types; section 7

* Changed: section 7 replaces "Program targets and allocation". The tape
  types are named String, Array, Hash and Tre; there is no heap type and
  no fallback allocator. Ruby's syntax stays: the compiler places memory.
  String's `<<` rebinds, nested containers hold pool runs behind handles,
  long-lived containers own a SlicePool so delete frees, and other stores
  that would outlive their tape are compile errors naming copy_to.
  1.6 and 5.4 are rewrapped after the rename.
* Why: the user's decision. Goose has no heap at any layer (§1.2), and a
  Ruby programmer should write Ruby without learning a second set of
  types; implicit copies happen only where they are bounded and freed.

## 2026-10-28: programs always run without a collector

* Changed: removed --no-gc; every program traps heap allocation and uses
  no collector. Supported program targets are Linux x86_64 and aarch64.
* Why: tape memory is the only program memory model, with no GC escape.
  The compiler executable keeps its independent collector choice.

## 2026-10-28: a local task takes a handed-off value

* Changed: 5.1 lets a local task capture a non-Share value its spawner
  hands off: spawned once directly in the group block, never read or
  assigned by the spawner after the spawn. IyiTask handles are Share.
* Why: the compiler now enforces 5.1 for local tasks, not only parallel
  ones. A server hands an accepted socket to its handler task and a pipe
  end goes to the task that uses it; both are moves, not shared borrows.
  Completion broadcast (5.2) needs task handles that other tasks wait on.

## 2026-10-27: board messages are Copyable, packed as one image

* Changed: 5.6 names the message property Copyable (Goose's flat): a
  finite, self-contained packed form, inferred by the compiler at post,
  take, poll and limit. A post packs counts, fields, union tags and live
  elements of Str, Ary and Tre into one owned image, sized before
  publication with the source unchanged; take unpacks fresh containers.
  Self-containing types and user link fields are refused; only Tre's own
  stop boundaries cross, open -1 kept. Empty values count under the
  limit; per-message bounds are published and exceeding one is 4.2.
  Packing is not the to_bytes image. 5.2 notes there is no cross-type
  order, but a task's completed posts precede its later calls.
* Why: a review found that "flat" meant two things in ris (Goose's
  property and @[Tape::Flat] raw bytes), that "copied whole" left nested
  Str pointers and cycles open, and that limit skipped the type check.
  Copyable follows Ruby's -able names and Ractor's "copy" for messages.

## 2026-10-27: board messages are flat; Ary and Tre allowed

* Changed: 5.6 calls board payloads flat, as Goose does, and admits
  Ary(T) and Tre(T) of flat T beside Str: each is copied whole in and
  out, and Tre links stay inside the copy. The compiler checks flatness
  at post and take; no marker type or annotation.
* Why: refusing Ary was never decided; the inbox rule had allowed what
  copy_to accepts. Goose queues take flat variable-size arrays, and
  copy_to already copies Ary and Tre (1.7). Goose's ban on index types
  does not apply: a Tre's links point only into itself.

## 2026-10-27: reviewed board contract and task-local resources

* Changed: 5.1/5.3 require Share captures or independent checked copies
  for every task, including local tasks and reached state. std managers
  keep per-task copies or serve copied messages from one owning task.
  1.4 includes checked boundary copies; 4.1 retains copyable results
  and copies them to each reader's tape.
  5.2 fixes canonical specialized keys, union wrappers, cancellation
  signatures, Nil outcomes, linearized limits and publication FIFO.
  Mail and limits survive tasks/groups; quits are accepted Job variants.
  5.6 fixes cancellation/data/timeout priority, recursive generated copies,
  claims/rollback and GC/no-GC storage. Resources never cross tasks:
  HTTP uses N own-listener SO_REUSEPORT tasks; pipe and socket races use
  one-task OS IO on the poller. No resource move, owns: or task.take.
* Why: the review found ambiguous outcomes and queue identities, unsafe
  reuse of single-owner inbox mechanics and std ports needing resource
  transfer. The chosen resource model instead keeps every resource with
  its opener. These rules settle the layout and port prerequisites before
  implementation. This entry supersedes the earlier RisBoard entry where
  they differ; doc/MESSAGES.md and TODO.md follow these choices.

## 2026-10-27: RisBoard, Goose's typed queues, replaces the inbox design

* Changed: 5.2 is RisBoard: one process-wide queue per message type,
  owned by no task; post never waits and answers false when full,
  take waits, take(T, ms) and poll answer {T?, Bool}, limit sets a
  count limit. 5.6 names where ris differs from Goose: fibers in
  groups, cancellable take, Str copied in and out, nil on a miss,
  resources stay in their task. 1.4 names board messages as copies;
  1.5 drops the actor destination note.
* Removed: 5.5 (RisActor), and from 5.2 and 5.6 RisInbox, RisWorker,
  RisSemaphore, RisEvent, request/reply, byte budgets, owns:,
  task.take and the ordered group drain. 5.5's number stays unused.
* Why: the inbox design grew owners, handles, close order, replies and
  resource moves, each to answer who owns a message. Goose answers it
  with one queue per type and copied values, so none of that is
  needed. Copying Goose instead of inventing keeps the model small.
  This entry supersedes every earlier 2026-10-27 entry on messages.

## 2026-10-27: 5.2 points to doc/MESSAGES.md

* Changed: 5.2 names doc/MESSAGES.md, not TODO.md, for the mechanisms.
* Why: the design moved out of a 190-line TODO item, so TODO keeps one
  item per step as its rules ask.

## 2026-10-27: message budgets, result take and drain registration

* Changed: 5.2 and 5.6 settle the five round 1 choices: aligned deep-copy
  accounting and inbox defaults, requester-side reply_bytes, checked
  one-shot resource result take, bounded FIFO semaphores, plain outcome
  unions with colliding data refused, and dynamic registration in drain.
  Oversized reply yields Full without copying or closing the reply slot;
  a smaller reply may retry while the requester keeps waiting. Physical
  exhaustion remains 4.2. Group end gives order, not termination.
* Changed: TODO replaces these open choices with sizing/copy plans,
  result-slot ownership/cleanup, atomic sealing and implementation gates.
* Why: agents need one safe form for each case and runtime storage needs
  fixed accounting and lifecycle rules. Alias-safe result publication is
  required before a take; wakeups cannot consume cancelled permits. Drain
  may append work but must seal against racing registrations. This entry
  supersedes earlier claims that reply never yields Full, result take and
  byte accounting are open, or drain registration is still undecided.

## 2026-10-27: reviewed message contract and runtime group shutdown

* Changed: 5.2 gives normal group shutdown to the runtime: wait for plain
  tasks, close inboxes in creation order and await each worker/actor's
  drain, join, discard and retire. Early exit cancels and wakes before
  joining. Owner death discards sooner; graceful close retains mail.
* Changed: 5.2, 5.5 and 5.6 define transport identity, creating-task thread
  affinity, worker-local state and scratch reset, transactional receive,
  pinning, slot generations and GC root clearing. Send ignores cancel;
  waits order Cancelled, data, Closed and TimedOut. Capacity starts at 1;
  request supplies rendezvous. Events latch and broadcast; semaphores
  count permits; omitted deadlines wait forever, 0 polls, negatives fail.
* Changed: 5.6 makes accepted requests survive caller timeout/cancel,
  resolves Request arms uniquely and defines live duplicates vs expired
  reply tokens. owns: moves resources into new tasks, workers or actors;
  later creator use is refused. Task.value never moves a resource;
  checked one-shot result take remains open. 4.1 qualifies result copies.
  Byte sizing and remaining mechanism choices are explicit TODO work.
* Why: the contract review found contradictions that would invalidate
  pool layouts and std ports. Joining alone proves no exclusive resource
  ownership, clearing on close loses mail, and cancelling only after join
  cannot end a waiting worker. This entry supersedes conflicting claims
  in earlier 2026-10-27 entries, including owner/group end, release on
  close, send cancellation, joined-result moves and settled outcomes.

## 2026-10-27: 5.6 message outcomes

* Added: 5.6 settles the open points: error order, slot generations,
  monotonic waits (0 polls, negative is 4.2), Full by count or a byte
  budget, request results and R from the Request variant, Expired and
  double replies, self-request refused, actor start from a state type
  and init block, resources moving only as a joined task's result,
  handles across threads, GC roots for pool slots.
* Why: implementers and agents need one answer per case. A cancel
  must lose no message; a stale handle must never reach a reused slot;
  a byte budget keeps Full a recoverable answer and leaves 4.2 for real
  exhaustion; a joined child cannot use what it returned, so its result
  is a checked move.

## 2026-10-27: RisActor, the main tool for messages

* Added: 5.5 RisActor, a RisWorker whose receive loop the compiler
  writes: state built in place in the worker, one message per scratch
  reset, in-place mutation, no waits in a handler, a panic ends it.
  1.5 says a checked destination write (copy_to, a destination writer)
  may reach an outer owner from local scratch; a scratch handle may not.
* Why: one message, one scratch tape matches ris's one tape per request
  and is Goose-shaped (a state owner beside short-lived data stacks).
  A handler is easier for an agent to write right than a receive loop.
  Returning state would copy it per message; in place it does not.

## 2026-10-27: RisWorker, no select, group end and limits

* Changed: 5.2 gives `g.new_worker` a RisWorker (a task owning an
  inbox), says main makes inboxes in its own group, drops select,
  wakes semaphore and event waiters with Cancelled at the group's end,
  keeps Cancelled out of send and asks one published byte limit for
  queued messages.
* Why: new_worker returns what its name says. One receiver and tagged
  messages cover several sources without select, as in Erlang, and
  spare the compiler's select lowering. A send never waits, so it has
  nothing to cancel. 4.2 asks published limits.

## 2026-10-27: group methods named new_*

* Changed: 5.2's `g.inbox` is `g.new_inbox` and `g.spawn_inbox` is
  `g.new_worker`, a task owning an inbox.
* Why: a noun method without arguments reads as a getter (`g.event`
  as the group's one event), and spawn says only that something
  starts. new_* names the object you get, as Ruby's Thread.new does.
  ris drops spawn for g.new_task when Channel goes (TODO.md).

## 2026-10-27: RisQue becomes RisInbox, made by its group

* Changed: 5.2 names the queue RisInbox(T). `g.inbox` makes one owned
  by the calling task, `g.spawn_inbox` one owned by the new child; the
  inbox ends with its group g.
* Why: an inbox has one receiver, which "queue" (Ruby's Queue has
  many) does not say. Making it only through a group gives every inbox
  an end, as g.spawn does for tasks (iyi III.4.1).

## 2026-10-27: owned message queues replace Channel

* Changed: 5.2 replaces iyi's Channel with RisQue(T). The making task
  owns a queue and alone receives; others hold a Share send handle.
  Send copies per message and never waits; receive copies to the
  owner's tape. Any holder closes and the owner drains, as with
  Channel; the owner's end discards. RisSemaphore and RisEvent take
  over Channel's other jobs: connection limits, back-pressure and done
  signals. 1.4 names queue messages beside copy_to as the copies.
* Why: a waiting send, rendezvous, send in select and many receivers
  each hold a message no single tape owns. ris chooses one receiver
  per queue and copies at both ends, so a message outlives the
  sender's tape. This diverges from iyi; Goose and Koja inform it.
  Ris* names ris runtime objects and leaves Que, Queue, Semaphore and
  Event to programs; Tape* names values on a tape, which a queue is
  not. Names may change once the model works.

## 2026-10-26: 5.2 no longer cites TODO 7

* Changed: 5.2's tape messages "come with TODO 7" now say they are open
  work in TODO.md.
* Why: TODO.md dropped its numbered steps; the item is now named there.

## 2026-10-26: the cassette metaphor

* Added: the opening lines name the tape as a half-joking cassette
  metaphor, to keep in mind only while recording (allocating).
* Why: the name invites the picture; it should help, not mislead.

## 2026-10-26: numbered sections and rules

* Added: sections are numbered 1-6, rules N.M; numbers never change.
* Why: code, errors and commits can cite one rule (TAPE_SPEC 2.3).

## 2026-10-26: growth reserves address space

* Added: each growing value's stable space is an address-space
  reservation committed on use, on every platform (Goose §1.2, §10.4).
* Removed: growth moves from RIS_TAPE_STATS; growth no longer moves.
* Why: the first growth moved viewed values off the tape. Goose keeps
  views valid across growth by reserving, not by refusing views.

## 2026-10-25: classes stay, on the tape

* Was: structs, unions and pools replace heap classes; copy_to refuses
  classes. Now: class instances are tape values allocated by new on the
  active tape, rooted like views, never moved, not Share; finalize is
  refused; copy_to copies them deep, splitting all sharing, and refuses
  self-reaching class types.
* Why: dropping classes would break iyi and Crystal code and the agent's
  habits for little gain; the heap, not the class, is what tape removes.
  An identity map was weighed with Codex and rejected: a class-only map
  still splits shared Ary handles, cannot rebase interior views, and
  Goose clones no graphs (§3.9, §4.1-4.3). One rule, split all sharing,
  is predictable; cycles are refused. Partial copies are discarded on
  the destination too, and copying runs no user code. The copy rules
  are one bullet with the build-on-destination rule.

## 2026-10-25: aliasing, sharing, messages, exit, byte images

* Added: Ary, Tre and builders are handles; assignment and arguments
  alias, only copy_to copies; Str is read-only. The spec is the target
  contract, gaps are in TODO.md. Byte images are checked field by field
  and never published in part. Runs with self-relative links never move.
* Changed: sharing is iyi's Share, "frozen" is gone; channels carry only
  Share values until TODO 7. exit runs the calling task's defers, as
  iyi III.1.4; only fatal errors skip cleanup.
* Why: a Codex review found assignment, writability, queued message
  ownership and byte validation unstated, and ris's exit differed from
  iyi without a tape reason. The code already aliases (Ary and builders
  hold one state pointer); Share already defines read-only data.

## 2026-10-25: reuse iyi's rules instead of restating them

* Changed: errors, panics and defer cite iyi III.1-III.1.4; the fatal
  message is iyi's panic print; signals are std/signal's; init order is
  iyi III.5; data races are iyi's Share (III.4.4); messages use iyi's
  Channel, select, ChannelClosed and Cancelled (III.4). ris states only
  what tape adds: region release, copies to the receiver, full queues.
* Changed: "a fiber may outlive its spawner" is replaced by iyi's group
  rule (III.4.1): a task never outlives its group; long work runs in a
  longer group, such as main's. "main's return ends all fibers" is gone
  with it, since main's group joins its tasks.
* Why: iyi already builds these; two specs saying the same thing drift
  apart, and the fiber rule contradicted iyi. ris reuses iyi where it
  fits and designs only what tape needs.

## 2026-10-25: copy_to matches the code

* Was: copy_to deeply copies, keeps aliases and rebases internal links.
  Now: build on the destination where an API can (writers, in-place
  append), else copy_to copies Str bytes and Ary/Tre/@[OnTape] fields
  deep; no aliases kept; pointers, classes, self-relative links refused.
* Why: the old text promised more than src/iyi/tape.iyi does (no identity
  map, no link rebasing). Goose builds at the destination and copies only
  explicitly (§4.1-4.3); self-relative links cannot be copied (§3.9).
  Refusing classes and self-relative links is open work in TODO.md.

## 2026-10-25: failure and exit rules, spec replaces tape docs

* Added: raise unwinding with ensure LIFO and region release; panic data
  copied to the receiver; exhaustion checked before mutation with an
  allocation-free fatal message; exit, fatal errors and signal handlers;
  recursion per Goose §7.8; pending result regions outside callee
  rollback (§10.3); refusal of runtime-sized growing collections;
  closures, bounded queues, thread-locals and FFI callbacks; tooling.
* Changed: Goose citations are informative; to_heap is a migration path
  and copy_to the suggested repair; root structs labelled as planned.
* Why: a review with Codex against Goose and iyi found the spec silent on
  what happens when execution fails or stops, and on where closures,
  queues and task records live without a heap. Without those rules a
  no-GC runtime cannot be built correctly.

## 2026-10-26: the tape named as Goose's data stack

* Changed: the Goose citation line says the tape is Goose's data stack.
* Why: Goose calls it a data stack; without the mapping a reader cannot
  find the tape in Goose's text.
