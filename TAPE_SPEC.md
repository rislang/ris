# ris tape memory
ris uses static data, scoped tapes and typed pools, no GC or general heap.
[Goose](doc/reference/goose/README.md) citations inform; only rules here
apply. A GC path (to_heap) needs a migration mark; suggest copy_to.
## Storage and lifetimes
* Main and each fiber own an implicit tape. Scope exit restores scratch;
  retained results stay on their destination owner. Suspension retains live
  storage. Every exit, normal or unwinding, releases owned regions once.
* Tape types: Str, Ary(T), Tre(T), builders, scanners, views, @[OnTape]
  structs; all obey the root rules. Structs, inline tagged unions and pools
  replace heap classes; dispatch and union payloads never box.
* Libraries borrow caller input and build results on the caller's owner;
  nested tape blocks share it. A pending result's region is outside callee
  scratch and its rollback (Goose §10.3). local_tape owns separate scratch;
  nothing rooted there escapes or mutates outer tape containers.
* .ri text literals are static Str; interpolation builds Str on the active
  tape. Read-only text parameters borrow Str, without a String copy.
* copy_to(owner) deeply copies, keeps aliases and rebases internal links;
  it cannot extend an external borrow. Cycles or resources need a checked
  copy routine. No implicit heap fallback or GC roots.
* Program data initializes once, in order, never suspending or seeing
  incomplete values; its stores obey owner provenance.
## Owners and stable growth (Goose §1.3, design/root_structs.md: planned)
* @[Owner] requires a named lexical/program declaration, built in place.
  Arguments borrow; results may borrow an existing owner, never a local.
  Refuse owner copies, moves, whole assignment, by-value calls, temporaries,
  nested owning fields, owners in arrays/unions; suggest borrowing instead.
* Each live growing component owns stable space (sizes: backend policy;
  disjoint lifetimes reuse it); growth never moves published elements.
  A runtime-sized collection of growing values is refused: use SlicePool.
  Roll back partial construction; refuse grow/shrink of the target during
  in-place construction, via helpers or aliases (Goose §4.2-4.3).
* No whole-owner byte image, raw copy/equality, FFI layout or transfer.
## Roots (Goose §9.1-9.2)
* Track (owner, field path) through aliases, branches, holders, calls and
  results; joins keep every alternative; inexact roots bound lifetime only.
* Every source root outlives every possible destination; inexact stores
  check each read-back candidate, caller storage behind parameters included.
  Branch-local and temporary storage cannot escape; loops see earlier rounds.
* Refuse shrink/clear/replacement with live views or holders, across calls,
  aliases and earlier operands (§5.1-5.2). Grow-shrink views stay local.
* Check every call target after specialization (generics, dispatch): its
  allocation, roots, shrink, suspension, without annotations (§10). Unknown
  targets and iyimod need checked contracts. Unproved: safe form and chain.
* Recursion (§7.8): no owner, growing local or parameter, temporary or
  pending result is live at a call into a cycle (callbacks too): pass scratch.
## Failure, cleanup and exit (Goose §7.9, §9.3)
* Errors are unions. raise unwinds: ensure runs LIFO on current locals,
  then frame regions are released; panic data and task results are copied
  to the receiver first. No unwound frame resumes; raise in cleanup is fatal.
* Exhaustion and bad sizes are checked before mutation, with overflow-safe
  arithmetic; they end with an allocation-free fatal message, no fallback.
  Limits for tape bytes, regions, tasks and native stack are published.
* Fatal errors and exit skip user cleanup; main's return ends all fibers.
  Signal handlers only set flags; work runs later in normal code.
## Concurrency and boundaries (Goose §11.2)
* Mutable state belongs to its worker/fiber; build owners there. No shared
  mutable owner, implicit global copy or snapshot. Static or frozen program
  data may be shared read-only, checked per owner.
* Messages copy flat data into receiver-owned storage. Queues, task records
  and wait nodes live in runtime typed pools; queues are bounded and send
  reports full, closed or cancelled. A failed receive keeps the message.
* Callbacks borrow their environment for the call only; an escaping
  closure copies captures to a named owner or task pool, never a borrow.
  A fiber may outlive its spawner. Thread-locals hold no fiber borrows.
* APIs expose Str, builders, Ary and tape structs, not raw pointers. FFI
  borrows have explicit lifetimes; retained foreign storage has an owner and
  cleanup. Never unwind across foreign frames; foreign threads attach first.
  Safety exceptions are marks with reasons, never a global switch.
## Pools, validation, tooling (Goose §5.4, §9.3-9.4)
* Pool(T)/SlicePool(T): typed slots/runs; free keeps values valid, stale
  views see typed replacements; generations only guard checked handles.
* Free keeps memory; reset obeys shrink rules. Run relocation is explicit:
  holders keep offsets and re-read; old views stay unchanged.
* Validate bounds, overflow and aligned membership before mutation; foreign
  storage is refused statically or at runtime. No uninitialized slots;
  self-relative links stay in one region. Validate external byte images.
* Pool free never closes a resource: resources have explicit cleanup.
* RIS_TAPE_STATS: owner paths, regions, committed peaks, pool waste, copies
  apart from growth moves. check.sh tests exit, panic, cancel, exhaustion.
