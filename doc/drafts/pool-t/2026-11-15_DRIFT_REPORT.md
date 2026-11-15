# Drift report: Pool(T) (SPEC 6.1), 2026-11-15

Draft: doc/drafts/pool-t/pool-t.md (revised after EGM review).
Built: src/ris/tape.ri (Pool, Pool::Handle), compiler sites in
src/compiler/iyi/semantic/, proofs in test/ris/ run by check.sh.

## Matches the draft

* API as listed: alloc, alloc_handle, free by index and handle, [] and
  []= by index and handle, get?, live?, size, Pool.next_gen.
* Parity generations, always stored, wrap skipping 0 to 2; free by
  index bumps the generation; double free and negative indices panic.
* Runtime messages and exit code 1, exactly as in the draft.
* Refusal texts for push, <<, realloc and Pool(File) exactly as in
  the draft; SlicePool shares the class check.
* Tests 1-4 as named; SPEC 6.1 reworded; CHANGELOG, UPSTREAM.md and
  AGENTS.md lines; triage.md citations fixed (N3).

## Drift

* The prelude has no UInt32 arithmetic or conversion (iyi primitives
  carry only Int32, Int64, UInt8, UInt64). Pool works on a generation's
  32 bits as an Int32 through two protected helpers, `Pool.bits` and
  `Pool.unbits`; the stored and exposed type stays UInt32.
* `Pool::Handle(T)` is `@[Tape::Flat]` and not `@[OnTape]`: like
  `Array::Link` it is a plain value, so any struct may hold it.
  `tape_in` skips its type argument: `T` only types it (a fifth
  compiler site the draft's first version did not list).
* The 6.5 element check first sat in `TapeChecker#check_fields` on the
  pool type. That refused every `Array(SomeClass)`, because the
  runtime's Array keeps class elements' runs in a SlicePool. It moved
  to `Call#instantiate` at a `new` outside the runtime; the draft was
  updated to say so.
* test/ris/text_grow.ri held a `SlicePool(GrowingField)` of a class;
  6.5 now refuses it, so that check uses an `Array(GrowingField)`.
* No goose-evals timing was taken (draft Step 6 of the first version);
  AGENTS.md asks for it at the end of a Now step, not per change.

## Left

* A same-type handle from another pool or a copy is not caught: a
  typed replacement by design (M9), proven in pool.ri.
* The wrap after 2^31 cycles of one slot is documented, not checked.
