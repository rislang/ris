# ris TODO

Work the docs promise but the code does not do yet. Rules: TAPE_SPEC.md.
Finish an item, then delete it here in the same commit.

## copy_to and retention
* `Object#copy_to` returns `self` (src/iyi/tape.iyi): a struct holding a
  class keeps a GC reference. Refuse it; suggest an `@[OnTape]` struct.
* Refuse copy_to of values with self-relative links (TAPE_SPEC.md).
* tape_escape_checker.cr still suggests `to_heap`: suggest copy_to(owner)
  or writing into the caller's builder.
* Build on a chosen owner without a copy (Goose root_structs.md,
  "Destination-aware library construction"); today only writers and
  `dest.append(render(...))` place in situ.
* Alias-keeping copies: relative links or pools, once their checks exist.

## Heap removal
* Mark every to_heap, `to_s` to String and @[TapeToHeap] site as a
  migration site; `ris heap` lists them; drive the count to zero.
* Hash, Array, String, IO, Exception: tape or pool backed replacements.
* Unions inline tagged, dispatch without boxing; refuse heap classes.

## Failure, cleanup and exit
* raise: ensure LIFO, then release regions; copy panic data to receiver.
* Raise inside cleanup is fatal; fatal and exit skip user cleanup.
* Exhaustion: checks before mutation, allocation-free fatal message; tape
  errors must not format through raise (tape.iyi). Publish limits instead
  of the fixed 64 MiB capacity.
* Signal handlers only set flags.

## Checker
* Pending result regions outside callee scratch rollback (Goose §10.3).
* Refuse runtime-sized collections of growing values; suggest SlicePool.
* Check every call target after specialization: allocation, roots,
  shrink, suspension; generics and dispatch included.
* Recursion per Goose §7.8: no live owner, growing local or parameter,
  temporary or pending result at a call into a cycle; callbacks count.

## Concurrency and FFI
* Queues, task records and wait nodes in runtime typed pools; bounded
  queues; send reports full, closed or cancelled.
* Escaping closures copy captures to a named owner or task pool.
* Thread-locals hold no fiber borrows.
* FFI: no unwinding across foreign frames; foreign threads attach first.

## Tooling and tests
* RIS_TAPE_STATS: owner paths, regions, committed peaks, pool waste;
  count copies apart from growth moves.
* check.sh cases: exit, panic, cancel, aliases, dispatch, exhaustion.
* Old root refs in bench/ (GC_DESIGN.md, AI_FIRST.md): point to
  doc/archive/iyi/ when those benches are touched.
