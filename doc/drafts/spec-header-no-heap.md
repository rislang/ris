# Draft: remove the heap sentence from SPEC.md's header

## Change

Remove from SPEC.md's opening paragraph, leaving the sentences around it
unchanged:

    A heap path (to_heap) needs a migration mark; suggest copy_to.

Nothing replaces it. The header sentence has no rule number.

## Problem

SPEC 7.1 says "No heap, no collector, no fallback allocator, no heap
type", and the opening paragraph says "no GC or general heap". `to_heap`
is no heap path: `src/iyi/tape.iyi` copies on the current tape, and
AGENTS.md calls the name historical, to remove. So the sentence is false
as well as contradicting 7.1.

## Does anything rely on the mark?

The mark is `@[TapeToHeap]`, an annotation on a def. No rule and no check
relies on it, so the removal goes ahead:

* SPEC.md: no numbered rule names `to_heap` or the mark. The rules that
  retain data already name `copy_to` (7.6 among them).
* Compiler: only `heap_census.cr` reads the annotation, to label sites
  for `ris heap`. A probe compiled marked and unmarked `to_heap` defs
  alike; the comment at `program.cr:1413` claiming a refusal is stale.
* Tests: `test/ris/check.sh` requires the census labels; tests and
  benches still carry the mark. They are not rules, and go with the follow-up.

## Alternatives

* Replace it with "to_heap is a historical copy, to remove": rejected.
  SPEC is the target contract; open work belongs in TODO.md.
* Remove `to_heap` and the mark in the same change: rejected. It touches
  the checker, census, tests and benches, and the false sentence need not
  wait for it.
* Keep the sentence until then: rejected. It tells agents a false rule.

## Non-goals

No compiler, test or bench change. Removing `to_heap`, the mark and their
census reasons is a TODO.md item added in the same commit.

## Risks

The SPEC goes silent on an API that survives. The TODO item owns it,
including:

* `call_error.cr:740,839` still suggest `.to_heap`, as does
  `spec/compiler/tape_spec.cr:33`, and agents follow errors.
* `tape_shrink_checker.cr` treats `to_heap` as a copy to an owner and skips
  the SPEC 1.9 refusal. Probes returning it from a def and keeping it from
  a loop round read correct text and a store out of a `tape` block is
  refused; that is evidence against dangling, not proof.
* `heap_trap to_heap` (`test/ris/check.sh:1917`) passes on a compile error:
  `test/ris/to_heap.ri` stops at a refused `HeapHit` field.
