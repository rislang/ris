# ris tape memory
The tape name is half a joke, after old cassettes: picture one only while
recording. Reading needs no picture; rewinding happens on its own.
ris uses static data, scoped tapes and typed pools, no GC or general heap.
[Goose](doc/reference/goose/README.md) citations inform; the tape is Goose's
data stack. iyi's rules,
cited as [iyi](doc/reference/iyi/source/SPEC.md) and a section (v0.19.1),
apply as written; only what ris adds is stated. Reuse iyi before designing
anew. A GC path (to_heap) needs a migration mark; suggest copy_to. This
is the target contract; what the code does not meet yet is in TODO.md.
Cite a rule by its number (TAPE_SPEC 2.3). Numbers never change: a new
rule goes last in its section; a removed one leaves its number unused.
## 1. Storage and lifetimes
* 1.1 Main and each fiber own an implicit tape. Scope exit restores scratch;
  retained results stay on their destination owner. Suspension retains live
  storage. Every exit, normal or unwinding, releases owned regions once.
* 1.2 Tape types: Str, Ary(T), Tre(T), builders, scanners, views, @[OnTape]
  structs and class instances; all obey the root rules. Dispatch and union
  payloads never box.
* 1.3 Classes stay: new allocates the instance on the active tape, checked
  before initialize; a reference is a root like a view. Instances are fixed size
  and never move; finalize is refused (resources have explicit cleanup); class
  instances are not Share. Long-lived ones are built on their owner's tape
  (Program.tape) or copied there with copy_to.
* 1.4 Ary, Tre and builders are handles to shared state: assignment and
  arguments alias data, length and capacity, so growth through b shows through
  a; Str and views alias their bytes. Only copy_to and inbox messages (5.2)
  copy; Goose's implicit value copies (§4.1) do not apply. Str is read-only.
* 1.5 Libraries borrow caller input and build results on the caller's owner;
  nested tape blocks share it. A pending result's region is outside callee
  scratch and its rollback (Goose §10.3). local_tape owns separate scratch;
  nothing rooted there escapes or mutates outer tape containers. A checked
  destination write may: copy_to(owner) or a destination writer puts the
  bytes on that owner, never a scratch-rooted handle (5.5).
* 1.6 .ri text literals are static Str; interpolation builds Str on the active
  tape. Read-only text parameters borrow Str, without a String copy.
* 1.7 Build retained data on its destination (writers, in-place append), else
  copy_to(owner) deep-copies Str bytes, Ary/Tre/@[OnTape] fields and class
  instances, splitting all sharing and extending no borrows. It keeps concrete
  types and inherited fields and runs no initialize or callbacks. Refuse
  pointers, self-relative links and self-reaching class types (via collections,
  unions or subclasses): build those on the destination with Ary nodes and
  indices. Publish only complete results; discard partial destination storage on
  failure; deep chains never overflow the stack.
* 1.8 Program data initializes in iyi III.5's module order, once, never
  suspending or seeing incomplete values; stores obey owner provenance.
## 2. Owners and stable growth (Goose §1.3, design/root_structs.md: planned)
* 2.1 @[Owner] requires a named lexical/program declaration, built in place.
  Arguments borrow; results may borrow an existing owner, never a local. Refuse
  owner copies, moves, whole assignment, by-value calls, temporaries, nested
  owning fields, owners in arrays/unions; suggest borrowing instead.
* 2.2 Each live growing component owns stable space (sizes: backend policy;
  disjoint lifetimes reuse it); growth never moves published elements. Its space
  is an address-space reservation committed on use (Goose §1.2, §10.4), on every
  platform; views stay valid across growth. A runtime-sized collection of
  growing values is refused: use SlicePool. Roll back partial construction;
  refuse grow/shrink of the target during in-place construction, via helpers or
  aliases (Goose §4.2-4.3).
* 2.3 No whole-owner byte image, raw copy/equality, FFI layout or transfer.
## 3. Roots (Goose §9.1-9.2)
* 3.1 Track (owner, field path) through aliases, branches, holders, calls and
  results; joins keep every alternative; inexact roots bound lifetime only.
* 3.2 Every source root outlives every possible destination; inexact stores
  check each read-back candidate, caller storage behind parameters included.
  Branch-local and temporary storage cannot escape; loops see earlier rounds.
* 3.3 Refuse shrink/clear/replacement with live views or holders, across calls,
  aliases and earlier operands (Goose §5.1-5.2). Grow-shrink views stay local.
* 3.4 Check every call target after specialization (generics, dispatch): its
  allocation, roots, shrink, suspension, without annotations (Goose §10).
  Unknown targets and iyimod need checked contracts. Unproved: safe form and
  chain.
* 3.5 Recursion (Goose §7.8): no owner, growing local or parameter, temporary or
  pending result is live at a call into a cycle (callbacks too): pass scratch.
## 4. Failure, cleanup and exit (iyi III.1, III.1.4; Goose §7.9, §9.3)
* 4.1 Errors, panics, defer and exit are iyi's: defer runs innermost first on
  normal scope exit, panic unwind and exit (the calling task's only), on current
  locals; a panic is caught at a task boundary. ris adds: frame regions are
  released after the defers; panic data and copyable task results are
  copied to the receiver first (resources: 5.6). A panic in cleanup is fatal.
* 4.2 Exhaustion and bad sizes are checked before mutation, with overflow-safe
  arithmetic; they end as iyi's panic print (allocation-free), no fallback.
  Limits for tape bytes, regions, tasks and native stack are published.
* 4.3 Fatal errors skip user cleanup. Signals are std/signal's: the handler sets
  a flag and wakes a pipe; work runs in a task.
## 5. Concurrency and boundaries (iyi III.4; Goose §11.2)
* 5.1 Tasks start in an iyi group and never outlive it (III.4.1); work that
  outlives its caller runs in a longer group, such as main's. Data races are
  iyi's Share check (III.4.4). ris adds: owners are built on their task's tape;
  no shared mutable owner, implicit global copy or snapshot. Only Share values
  (III.4.4) are shared: Str and program data no method writes after init,
  checked per owner. Ary and its views write through and are never shared; ris
  has no freeze.
* 5.2 Tasks pass messages through `RisInbox(T)`, after Goose's typed
  queues (§11.2) and Koja's process boundary
  ([MEMORY-MODEL.md](doc/reference/koja/design/MEMORY-MODEL.md)).
  `g.new_inbox` makes one owned by the calling task; `g.new_worker` makes
  a RisWorker owning one. Only the owner receives: refuse known misuse,
  else panic with a hint to send or create an inbox in the receiving task.
  Main uses its own group. Capacity is at least 1; refuse 0 with a hint
  to request for rendezvous; negatives and overflow follow 4.2.
  Send copies payloads by 1.7 into inbox-owned per-message storage; receive
  copies them out. Resources and owners are refused recursively. Runtime
  handles and reply tokens copy identity, never their records; Request
  envelopes copy only their payload.
  Send handles, workers and actors are Share regardless of payload type;
  sharing a handle extends no tape borrow (3.x). They cross threads;
  workers and actors run on their creating task's thread.
  Send never waits and ignores task cancellation: Closed before Full.
  Receive copies to the owner's current tape before releasing queued mail.
  Any holder may close: refuse sends, retain mail to drain, then Closed.
  Owner death discards unread mail and closes unanswered requests even
  while the group lives. At normal group block end the runtime waits for
  plain tasks, then closes inboxes in creation order, waiting for each
  worker or actor to drain and finish before closing the next; it joins,
  discards remaining mail and retires records. During drain, members and
  their children may create work: new inboxes append to the closing order;
  await live plain tasks before closing each next inbox. Seal registration
  only after all children finish and the closing order is exhausted; later
  new_* panics with a hint to a live outer group. No manual close or compiler
  proof is required. This guarantees order, not termination: a plain task
  waiting on a later worker's shutdown, or endless worker creation, can
  keep the group from ending. Early exit cancels children and wakes waits
  before joining, discarding and retiring; new tasks inherit cancellation,
  new inboxes/workers/actors are refused. Nested groups follow the same
  order; stale handle operations yield Closed.
  g.new_semaphore(n) has initial and maximum permits n >= 1: acquire takes
  one; release returns one, wakes the oldest live waiter and panics above
  the maximum. Newcomers cannot bypass waiters; cancelled waits take none.
  hold releases on every exit after successful acquire. Pre-acquire permits
  to start empty. RisEvent latches on fire and broadcasts; repeated fire is
  harmless. acquire/wait answer Nil, Cancelled or TimedOut; release/fire
  answer Nil, fired? Bool. All yield Closed after group end.
  receive(), acquire() and wait() have no deadline; a ms argument uses a
  monotonic clock, 0 polls, negatives follow 4.2. ris has no select or
  Channel. Runtime records live in typed pools; mechanisms remain in TODO.
* 5.3 Callbacks borrow their environment for the call only; an escaping closure
  copies captures to a named owner or task pool, never a borrow. Thread-locals
  hold no fiber borrows.
* 5.4 APIs expose Str, builders, Ary and tape structs, not raw pointers. FFI
  borrows have explicit lifetimes; retained foreign storage has an owner and
  cleanup. Never unwind across foreign frames; foreign threads attach first.
  Safety exceptions are marks with reasons, never a global switch.
* 5.5 `g.new_actor` makes a RisActor, a RisWorker whose receive loop the
  compiler writes. From `state: S` it declares one named worker-local
  state in place with S.new, then runs init with copied captures (5.3).
  Startup never waits or publishes state borrows; sends may queue during
  it. Owners are never startup values or actor fields (2.1); resources
  enter only through owns: (5.6). State and growing parts stay outside
  handler scratch (2.2). Each handler borrows state and one typed message;
  scratch resets after its defers on every exit, never freeing state.
  It mutates state in place and returns Nil; retain data with
  copy_to(state) or a checked state writer, never scratch roots (1.5, 1.7).
  Check no-wait transitively, including cleanup and foreign contracts:
  launch a task with copied input and receive completion, or use a worker.
  Launch and send do not wait; task captures retain no state/message borrow.
  Reply only through a typed Request. A startup or handler panic ends the
  worker and closes its inbox; partly changed state never resumes.
  Outside it is a RisWorker (5.2). Goose's root structs inform state
  ([root_structs.md](doc/reference/goose/docs/design/root_structs.md)).
* 5.6 Waits decide at one commit point: Cancelled, available data, Closed,
  then TimedOut. A wake transfers nothing. Receive publishes a complete
  copy or rolls back and keeps mail; success survives later cancellation.
  Active copies pin records; closure cannot recycle pinned storage.
  Full accepts nothing, by count or a positive per-inbox bytes: budget,
  default max(64 KiB, capacity * 4 KiB). Preflight charges root inline size
  once plus destination allocations and their headers, rounded to 8 bytes:
  compact live lengths, concrete class instances and split aliases. Charge
  reserved copies until commit/rollback; exclude unused address reservation,
  page slack, pool bookkeeping and scratch. Publish separate finite runtime
  limits for excluded storage; bytes: is not an RSS cap. Arithmetic and
  physical exhaustion follow 4.2. Handles carry type, slot
  and generation; wrap retires the slot, stale handles never reach reuse.
  Runtime pools expose no payload views and keep occupied slots typed (6.x).
  GC roots cover active payloads and copies; clear only after committed
  receive, discard or rollback, never on graceful close alone.
  Refuse top-level message/reply alternatives overlapping Closed, Cancelled,
  TimedOut, Full or Expired, through aliases and base types too; suggest a
  wrapper struct, whose fields may hold them. receive answers T, Closed or
  Cancelled (also TimedOut when timed); successful data is not boxed.
  request waits for a copied reply: R, Full, Closed, TimedOut or Cancelled.
  Its argument must resolve to exactly one Request(M, R) union arm; refuse
  ambiguity with a hint to distinct tagged payloads. Both M and R obey 5.2.
  Only the runtime makes envelopes; plain send cannot forward a Request.
  Accepted messages survive request timeout/cancel; effects are not undone.
  Graceful close permits replies; owner death closes unanswered slots,
  while a committed reply survives it. request(..., reply_bytes:) sets a
  positive requester-side reply budget, default 64 KiB, outside inbox bytes.
  reply answers Nil on commit, Expired for retired/timed-out/cancelled tokens,
  or Full if the copy exceeds that budget. Expired and Full copy nothing;
  Full leaves the slot open for a smaller reply and the requester waiting
  until commit or its timeout/cancel. Duplicate committed replies while
  live panic. Physical exhaustion remains 4.2.
  Refuse known self-request, else check task identity and panic; suggest a
  local call, send or another task. Resources never copy as messages or
  through copy_to. owns: moves a resource at task start, also for workers
  and actors, e.g. g.new_task(owns: client): exclude surviving aliases and
  refuse later creator use, suggesting work in the receiving task or a
  message to it. Cleanup belongs to the receiver. Returning a resource
  moves it into a checked result slot before child cleanup/tape release;
  exclude surviving aliases and transfer its cleanup obligation. Task.value
  refuses resource results with a hint to task.take. Only the group's owner
  may take such a result: join then move it once, copying other tape data to
  the caller; cancellation before claim consumes nothing. A second live
  take panics; retired handles yield Closed. Panic delivery is value's.
  Group end closes unclaimed resource results on normal and early exit.
## 6. Pools, validation, tooling (Goose §5.4, §9.3-9.4)
* 6.1 Pool(T)/SlicePool(T): typed slots/runs; free keeps values valid, stale
  views see typed replacements; generations only guard checked handles.
* 6.2 Free keeps memory; reset obeys shrink rules. Run relocation is explicit:
  holders keep offsets and re-read; old views stay unchanged. Runs holding
  self-relative links are never relocated (Goose §5.4).
* 6.3 Validate bounds, overflow and aligned membership before mutation; foreign
  storage is refused statically or at runtime. No uninitialized slots;
  self-relative links stay in one region.
* 6.4 External byte images (.load(bytes)) check lengths, alignment, union tags,
  spans and links (each to an element start in the image) before any value is
  published; invalid input yields none, never part. This is safety, not
  integrity: a checksum is the caller's (Goose §9.4).
* 6.5 Pool free never closes a resource: resources have explicit cleanup.
* 6.6 RIS_TAPE_STATS: owner paths, regions, committed peaks, pool waste, copies.
  check.sh tests exit, panic, cancel, exhaustion.
