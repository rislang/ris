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
  a; Str and views alias their bytes. Only copy_to copies; Goose's implicit
  value copies (§4.1) do not apply. Str is read-only.
* 1.5 Libraries borrow caller input and build results on the caller's owner;
  nested tape blocks share it. A pending result's region is outside callee
  scratch and its rollback (Goose §10.3). local_tape owns separate scratch;
  nothing rooted there escapes or mutates outer tape containers.
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
  released after the defers; panic data and task results are copied to the
  receiver first. A panic in cleanup is fatal.
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
* 5.2 Messages use iyi's Channel and select, ChannelClosed and Cancelled
  (III.4), and carry only Share values, no tape values. Tape messages (owner
  while queued, copy, release on close) are open work in TODO.md. Queues,
  task records and wait nodes live in runtime typed pools; a buffered queue is
  bounded and send reports full. A failed receive keeps the message.
* 5.3 Callbacks borrow their environment for the call only; an escaping closure
  copies captures to a named owner or task pool, never a borrow. Thread-locals
  hold no fiber borrows.
* 5.4 APIs expose Str, builders, Ary and tape structs, not raw pointers. FFI
  borrows have explicit lifetimes; retained foreign storage has an owner and
  cleanup. Never unwind across foreign frames; foreign threads attach first.
  Safety exceptions are marks with reasons, never a global switch.
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
