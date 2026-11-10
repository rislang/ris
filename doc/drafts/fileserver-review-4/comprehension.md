# Comprehension review (fourth draft)

Verdict: ready once the two Majors are fixed. Review 3 items are
answered.

## Major

1. Lines 334, 405-422, 431-443: the draft does not say who drops
   the body of a HEAD error answer (405, 404, 416, cap 500): the
   server, `format_head`, or FileServer skipping `text()` (551).
   Say it once, cite the line, and say what `Content-Length` a HEAD
   error answer carries. Test case 18 depends on it.
2. Lines 106-112, 202-205, 776-779: "forms" is used inconsistently.
   Give one table of what P1 tried (expression x def kind -> result)
   and map each gate file to an entry.

## Nits

3. Lines 264, 287-305: no rule sets `@state[2]` to 1; add it to
   rule 4.
4. Lines 358, 651: six sites cited, "seven `parse` defs" claimed
   (the count is right: also time.iyi:2463). Cite all seven.
5. Lines 299-300: "tape twin" is undefined.
6. Lines 413-414, 423: say whether step 8 also uses `validators`.
7. Lines 732-735, 811-813: "heap_trap" is undefined; cite check.sh.
8. Line 205: say directly that one file with five forms would stop
   at the first refusal.
