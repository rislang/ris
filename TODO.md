# ris TODO

Rules: TAPE_SPEC.md. Goal: no GC. Measure: test/ris/heap_budget.txt.

How to work (fewer tokens, faster to the goal):

* Demand first: fix only what a budgeted sample allocates. Run its
  census, take the largest heap site, move it to tape, lower its budget
  row in the same commit. A module nothing in the budget hits waits.
* One change, one gate: the lowered budget row, plus one --no-gc test
  only where the census cannot see the path (error paths).
* Replace, don't wrap: when a String API has a tape twin, grep the repo
  for callers. Few: move them to the tape API and delete the String API
  in one commit. Many: keep the wrapper for now.
* TODO holds open work only, one line per item; what is done lives in
  git log. Delete a line when its budget reaches zero.

## A. Budget to zero (do in this order: largest win first)

1. serve.ri 13, web.ri 12: remaining request objects and closures.
2. logline 4: IO, backend, logger and context mutex objects.
3. static-user-sites column to 0 for every row.

## B. Language pieces the budget needs (pull in only when A is blocked)

* Classes on the active tape (`new`), class copies on the owner; roots
  track references, finalize refused.
* First growth: no transfer of a viewed value (region.iyi tape_resize);
  refuse views across the first growth, non-Linux still moves.
* Escaping closures: codegen.cr ProcLiteral wrapper malloc into a pool.
* Concurrency (src/iyi/concurrency.iyi): task records, wait nodes and
  messages in pools; bounded queue reports full. Only what serve needs.

## C. Switch off the GC

1. Gate every budget row at 0 in check.sh with the gc_none trap
   (UPSTREAM.md); replace GC comparisons, keep checksums and ris-bench
   respond copy.
2. No GC by default: remove allocator fallback, exemptions, collector
   linkage (gc_none still allocates: prelude.iyi:7572). Link audit.

## Later (after C, not before)

Pool/SlicePool validation, FFI borrow/attach/unwind barriers, full std
module sweep (collections, IO, errors), 128-bit formatting, IDNA, URI
resolution, RIS_TAPE_STATS extras (owner paths, pool waste).

Known: spec/compiler/iyimod_spec.cr "carries the constants a module's
own code reads" fails: runtime constants appear in the constant list.
