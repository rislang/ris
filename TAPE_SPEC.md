# ris tape memory
The tape name is half a joke, after old cassettes: picture one only while
recording. Reading needs no picture; rewinding happens on its own.
ris uses static data, scoped tapes and typed pools, no GC or general heap.
[Goose](doc/reference/goose/README.md) citations inform; the tape is Goose's
data stack. iyi's rules,
cited as [iyi](doc/reference/iyi/source/SPEC.md) and a section (v0.19.1),
apply as written; only what ris adds is stated. Reuse iyi before designing
anew. A heap path (to_heap) needs a migration mark; suggest copy_to. This
is the target contract; what the code does not meet yet is in TODO.md.
Cite a rule by its number (TAPE_SPEC 2.3). Numbers never change: a new
rule goes last in its section; a removed one leaves its number unused.
## 1. Storage and lifetimes
* 1.1 Main and each fiber own an implicit tape. Scope exit restores scratch;
  retained results stay on their destination owner. Suspension retains live
  storage. Every exit, normal or unwinding, releases owned regions once.
* 1.2 Tape types: String, Array(T), RisTree(T), builders, scanners, views,
  @[OnTape]
  structs and class instances; all obey the root rules. Dispatch and union
  payloads never box.
* 1.3 Classes stay: new allocates the instance on the active tape, checked
  before initialize; a reference is a root like a view. Instances are fixed size
  and never move; finalize is refused (resources have explicit cleanup); class
  instances are not Share. Long-lived ones are built on their owner's tape
  (Program.tape) or copied there with copy_to.
* 1.4 Array, RisTree and builders are handles to shared state: assignment and
  arguments alias data, length and capacity, so growth through b shows through
  a; String and views alias their bytes. copy_to and checked boundary copies
  (4.1, 5.1-5.3, 5.6) copy; Goose's implicit value copies (§4.1) do not
  apply. String is read-only.
* 1.5 Libraries borrow caller input and build results on the caller's owner;
  nested tape blocks share it. A pending result's region is outside callee
  scratch and its rollback (Goose §10.3). local_tape owns separate scratch;
  nothing rooted there escapes or mutates outer tape containers.
* 1.6 Text literals are static String views; interpolation builds a
  String on the active tape. Text parameters borrow, never copy.
* 1.7 Build retained data on its destination (writers, in-place append), else
  copy_to(owner) deep-copies String bytes, Array/RisTree/@[OnTape] fields and
  class instances, splitting all sharing and extending no borrows. It keeps
  concrete types and inherited fields and runs no initialize or callbacks.
  Refuse pointers, self-relative links and self-reaching class types (via
  collections, unions or subclasses): build those on the destination with Array
  nodes and indices. Publish only complete results; discard partial destination
  storage on failure; deep chains never overflow the stack.
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
  released after the defers; panic data and copyable task results survive
  on retained result storage and are copied to each reader's tape (5.6).
  A panic in cleanup is fatal.
* 4.2 Exhaustion and bad sizes are checked before mutation, with overflow-safe
  arithmetic; they end as iyi's panic print (allocation-free), no fallback.
  Limits for tape bytes, regions, tasks and native stack are published.
* 4.3 Fatal errors skip user cleanup. Signals are std/signal's: the handler sets
  a flag and wakes a pipe; work runs in a task.
## 5. Concurrency and boundaries (iyi III.4; Goose §11.2)
* 5.1 Tasks start in an iyi group and never outlive it (III.4.1); work that
  outlives its caller runs in a longer group, such as main's. ris adds:
  every task, local or parallel, captures only Share values (III.4.4) or
  independent checked copies on its own tape (1.7), never mutable borrows.
  Check captures, receivers and reached program state transitively. Owners
  are built on their task's tape; no shared mutable owner, implicit global
  copy or snapshot. String and program data shared read-only have no writer
  after init, checked per owner. Array and its views are never shared; no
  freeze. Resources are opened, used and closed by the same task (5.6).
  A local task may take one value handed off: spawned once in its group
  block, never read or assigned by the spawner after the spawn; the task
  then owns it (an accepted socket, a pipe end), and no second local names
  it, nor a call before the spawn that may keep it. Task handles are
  Share. The block and the program methods and procs it calls (any proc
  of a called type) change no class variable or constant; a local task
  may set a scalar class variable (its spawner's thread), a thread may not.
* 5.2 RisBoard copies Goose's typed-queue transport (§11.2), not its thread,
  global-copy or abort model. Main and tasks use one process-wide queue per
  canonical specialized type across modules: aliases share a key, generic
  arguments distinguish keys. Bare unions are refused: use a nominal struct
  with a union field. post(v) uses the exact static type, no conversion or
  runtime-arm routing; roles use distinct nominal types, Job and Result.
  post(v) : Bool copies in: true on publication, false when full, nothing
  queued. It ignores cancellation and never waits for capacity; runtime
  locking and copying take time. take(T) : T | Cancelled waits for one;
  take(T, ms : Int64) and poll(T) answer {T?, Bool} | Cancelled:
  {v, true}, or {nil, false} on a miss; queued Nil gives {nil, true}.
  ms <= 0 polls; positive waits use a saturating monotonic deadline.
  limit(T, n : Int64) : Nil sets a count limit, unlimited until set;
  n <= 0 follows 4.2. Lowering keeps mail; posts fail while count >= n.
  Admission, limit and consumption are linearized; unpublished copies do
  not count. FIFO is publication order per type, a ris clarification;
  no taker fairness or cross-type order is promised. A task's completed
  posts still precede its later calls; a Done message does not prove
  that earlier jobs were taken. Mail and limits
  survive task/group end and cancellation. Mail lasts until taken or process
  end; limits last until changed or process end. No new, close, owner,
  handle or reply.
  Quit is a variant of Job: post one accepted quit per worker, then join;
  group end invents no quits and drains no queues. Completion broadcast
  uses IyiTask#value, subject to handle sharing and result-copy rules,
  not a timed wait. ris has no Channel, select or Mutex; see
  doc/MESSAGES.md.
* 5.3 Callbacks borrow their environment for the call only; an escaping closure
  copies captures to a named owner or task pool, never a borrow. Task
  closures obey 5.1, including captured handlers and receivers. std managers
  use independent per-task config/state, or one task owns state and serves
  copied board messages; no shared mutable autocert manager or IdleConns.
  Thread-locals hold no fiber borrows.
* 5.4 APIs expose String, builders, Array and tape structs, not raw
  pointers. FFI borrows have explicit lifetimes; retained foreign storage
  has an owner and cleanup. Never unwind across foreign frames; foreign
  threads attach first.
  Safety exceptions are marks with reasons, never a global switch.
* 5.6 ris uses grouped iyi fibers (5.1), not detached Goose threads; a waiting
  take parks its fiber. At one consume commit, cancellation wins, then data,
  then timeout, including poll and already-cancelled entry. Cancelled consumes
  nothing; partial copies and claims roll back. Data present at commit may win
  after a delayed deadline wake. Top-level Cancelled keys are refused: wrap that
  data in a nominal message. A message is Copyable: it has a finite,
  self-contained packed form (Goose calls this flat). Copyable types are numeric
  scalars, Bool, Char, Symbol, Nil, enums, String, Array(T) and RisTree(T) of
  Copyable T, and value structs or unions of these. String, Array and RisTree
  are handles; the board packs their live data, not pointers, so Copyable is not
  raw-byte safe (@[Tape::Flat]). The compiler infers it, with no marker, at
  post, take, poll and limit after specialization. A type that contains itself
  through fields, unions, Array or RisTree is refused: keep recursive data in a
  RisTree or in a node array with checked integer indices (2.2 still applies).
  User link fields (Array::Link and other self-relative links) stay refused as
  in 1.7; only RisTree's own stop boundaries cross, kept relative to the copied
  entries, with an open container's -1 and a stop equal to size preserved. A
  post packs counts, fixed fields, live union tags and live elements into one
  owned image, recursively, with no backing pointer and no spare capacity, sized
  with checked arithmetic before publication; the source and its aliases stay
  unchanged meanwhile. Each copied occurrence of a handle gets independent
  state, splitting sharing as in 1.7; an empty value carries its count and still
  takes one place under the limit. take unpacks fresh containers and bytes on
  the taker's tape, with capacity equal to size. Copies keep concrete types and
  enum values and run no user code. Count and packed-byte bounds per message are
  published; exceeding one follows 4.2, not false. Board packing is private and
  is not the to_bytes/from_bytes image. Owners, pointers, resources, closures
  and classes are refused at every depth, with the safe form named. A post
  publishes a complete copy or nothing; take copies out before removal. Claims
  prevent duplicate delivery and keep FIFO through failure. No view into runtime
  pools escapes. Private typed pools own message bytes without a general heap.
  Exhaustion follows 4.2. At process end queued copies are discarded without
  user callbacks; task cleanup and fatal errors still follow 4.1/4.3. A socket
  or pipe end never crosses tasks: no owns:, task.take, resource move or
  exception. An HTTP server uses N tasks, each opening its own SO_REUSEPORT
  listener on the same port and accepting and serving one connection at a time;
  N limits connections, with no permits or semaphore. Pipe and socket race IO
  stay in one task using OS facilities on the poller; board IO copies data.
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

## 7. Types, memory and Ruby syntax (doc/TAPE_TYPES.md; Goose §1.2, §3.7)

* 7.1 No heap, no collector, no fallback allocator, no heap type. Memory is
  static data, tapes, `Program.tape` and typed pools (Goose §1.2, §5.4).
  Programs build only for Linux x86_64 and aarch64; other targets fail at
  compile time. The compiler executable keeps its own GC.
* 7.2 The data types are String, Array, Hash and RisTree, on the tape. String
  is a read-only view of bytes; a literal views static bytes; building
  text (`+`, interpolation, `to_s`, `String.build`) writes on the current
  tape. Array is grow-only in its own reservation, never moving. Hash is
  open addressing in place, in insertion order. RisTree is a tree in one array
  with index links.
* 7.3 Ruby's and Crystal's syntax stays as written; the compiler places
  memory. A String local or field that gets `<<` reserves growing storage
  at its first append, copying its current text once; later appends grow
  in place and never move. A field's reservation belongs to its object's
  owner. Reading it gives a String view: after `t = s; s << x`, `t` keeps
  the old text, as a String is immutable. Rebinding starts a fresh
  reservation at the next append; text never appended reserves nothing.
  Bang methods rebind. A String::Builder that a program only appends to
  and reads back is refused, naming `text = ""`; one passed to a call or
  used for bytes stays.
* 7.4 Nested containers (`Array(Array(T))`, `Hash(K, Array(V))`) hold
  their inner arrays as runs of a SlicePool they own; `outer[i]` answers a
  handle to its run, so a change through it shows in the container. No
  view into a run outlives its next growth.
* 7.5 A long-lived container (a constant, a class variable, a field of a
  program-owned object) owns a SlicePool for what it holds. A store copies
  the value into a run of that pool; delete, clear and overwrite give the
  run back. Only this store copies implicitly.
* 7.6 Any other store of a tape value into something that outlives it is
  a compile error naming the forms that work: `copy_to(owner)` or a
  long-lived container (1.x, 3.x).
