# Zoom-out review, fifth draft

(Saved by the synthesizer; the reviewer had no write tool.)

Verdict: ready. No Blockers, no Majors.

Review 4 M1-M4 resolved (Memory table 503-527, Risks 691-693;
MAX_BODY clamp fileserver.iyi:46, 132, P14; P1 form -> gate table,
P13; outgoing_refusals.sh 747-776, check.sh:1197). Draft and code
agree (http.iyi:2221-2321, 2476-2504; fileserver.iyi:66-198;
TODO.md:222; router.iyi:527; answer.ri:26, 36; check.sh:851,
1205-1216). The fix sits at the right layer; nothing new invented.

Nits:
1. 391 vs 680: "about 50" vs "about 40" lines.
2. 630-632: module doc differs from fileserver.iyi:16-19.
3. Optional: `Keep` (155-204), `read_into` (548-570), helper list
   (597-608) duplicate code; cite file:line.
4. 345-348: the 1% rule plans for an unmeasured cost.
5. 3-5: say the draft is implemented in the working tree.
