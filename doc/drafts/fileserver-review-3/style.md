# Style review (third review)

Target: doc/drafts/fileserver-outgoing.md. No line over 80 chars.

No Blockers, two Majors.

## Major

1. Lines 7, 677-708: "P1-P9" cited, Evidence lists P1-P8.
2. Lines 230-232: "goose-evals", "the Now step" undefined; and the
   sentence says the `RIS_TAPE_STATS` gate "times" the copy, but it
   counts growth moves and side regions (20-22, 650-655). Say what
   each run measures.

## Nits

3. Line 532 "most used call": no count; cite one or rephrase.
4. Lines 474-476 "(found in P4)": P4 (693-698) does not record the
   `text[4] == ' '` finding.
5. Lines 225, 228 "stay right": say "stay valid".
6. Line 219 "buys nothing": informal; drop or justify.
7. Line 68 "turned up": state the finding plainly.
8. Lines 414-415, 422-423: stacked colons.
9. Lines 117-118: `"ZZZZZZZ"` used before explained.
10. Lines 14-17: "SPEC.md 1.1" vs "SPEC 1.1"; pick one.
11. Lines 540-542: clipped fragments ("Shrinking: the 500.").
12. Line 228: P4's 0 growth moves is Linux-only evidence; it does
    not cover the `owned_resize` moving case. Say "on Linux".
13. Lines 3-6: review history precedes the subject; move it above
    the item tables (710).
