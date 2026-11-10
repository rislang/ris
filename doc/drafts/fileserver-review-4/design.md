# Design review (fourth draft)

Verdict: ready after one Major wording fix. MB1-MB6 resolved; MB5's
new text adds an inaccuracy.

Checked: region.iyi:523-529, log.iyi:400-402, check.sh:64,
check.sh:1187-1188, http.iyi:2213-2256.

## Major

1. Lines 455-461, 627-629: "about 256 GiB ... that is
   `Server.answer`'s cost today with one builder" is wrong. Today
   Outgoing has one growing builder, `@body` (http.iyi:2225, 2231),
   about 128 GiB at 1024 answers; the new `@text` doubles it. Say
   so, or give `@text` a fixed capacity that skips the side reserve,
   and recheck P4's "0 side regions".
2. Lines 583-586: http.iyi:2214-2216 says the body is "the one value
   that grows"; false once `@text` grows. Replace that sentence.

## Nits

3. Lines 289-291, 300-304: after a refused line `@state[2]` stays 1;
   if a handler can rescue the raise, later calls fail. Clear it
   before raising, or say rescue is impossible.
4. Lines 627-628: align Risks with the fixed Memory paragraph.
5. Line 332: say the length check is skipped on bodiless statuses.
