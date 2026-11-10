# Structural review (fourth draft)

Target: doc/drafts/fileserver-outgoing.md. No Blockers.

Holds: heading levels, closed fences, tables, lines <= 80, P1-P12
cited at line 7 (MB6 range fixed), 304 lines (411-414) match the
table (436).

## Major

1. Lines 358, 650-651: Phase 1 says seven `parse` defs end in an
   `_answer` call; the std/time section cites six sites
   (time.iyi:3635-3639, 2457-2466, 3656, 3672, 3689, 3704). List
   all seven or fix the count.

## Nits

2. Lines 657, 678-679: Phase 1 and Phase 3 both insert a check.sh
   block near check.sh:1187-1188. Place Phase 3 relative to the
   Phase 1 block by name.
3. Lines 838-859: mapping targets still not exact headings (MB4
   "Log lines" is a paragraph label at 469; "(Memory)", "(Files)").
4. Lines 811-816: P11 and P12 are never cited from the body. Cite
   P11 from Risks (638-640) or Phase 1; mark P12 as a note.
5. Lines 127-131, 646: Phase 0 done-condition written twice; keep
   one, point to it.
6. Lines 234, 534: `MAX_FILE = 16_777_216_i64` given twice; keep it
   in Helper signatures.

No settled item is broken.
