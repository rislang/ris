# Comprehension review (third review)

Target: doc/drafts/fileserver-outgoing.md

Every section can be paraphrased; no Blockers.

## Major

1. Lines 132-136 vs 558-559: the Prerequisite says the draft "adds
   the failing gate", then that it is committed with the compiler
   fix; Phase 0 says "kept ready". Unclear who commits the file and
   where it waits.
2. Lines 288, 296-298, 307-308 vs 320: a 304 is decided at step 4
   ("nothing after it runs"), lines are written "only now" at step
   8, yet the table gives the 304 Last-Modified, ETag and
   Accept-Ranges. When and by what the 304 gets its lines is unsaid.
3. Lines 35-37 vs 183: Terms reserve "size" for the file's size, but
   `@size` holds `res.length`.
4. Lines 180, 206: `@state` packs three meanings in one Array; only
   index 2 is named; why an Array is unsaid.

## Nits

5. Line 7 cites P1-P9; Evidence ends at P8.
6. Lines 231-232: ris-bench, goose-evals, "the Now step" undefined.
7. Lines 98, 596: `@[OnTape]` undefined, yet decides UPSTREAM.md.
8. Line 172: "`as_tape` is the identity" assumes its purpose known.
9. Line 223: `Field` not introduced.
10. Lines 338, 544, 603: `MAX_CONNECTIONS` vs `max_connections`:
    same knob?
11. Lines 539, 548: "cases 14-15", "case 18" point forward silently.
12. Line 547: log "names the path and its size", but the field is
    `bytes: count` (351).
13. Line 561: "gated on its own" not linked to Terms (25-26).
14. Line 679: "minitest" without its gloss.
