# EGM Stage 7: Critic report (round 1)

Target: doc/drafts/spec-3.5-cycle-roots.md, lines 1..End.
Reviewers: design (2 Blocker, 6 Major, 4 Nit), structural (1 Blocker,
3 Major, 4 Nit), style (1 Major, 6 Nit); all completed. Deduplicated.

## Blocker

1. No "Alternatives considered" (design B1, structural 1). Weigh and
   reject: only narrow 3.5 and leave stores to 3.2/3.6; Goose's strict
   rule (a different pool at a back edge is an error at the call);
   per-activation checking; a `recursive` annotation as in Goose.
2. No Goals/Non-goals and no Risks (design B2, structural 2-3): valid
   programs still refused (replaced back-edge parameter); diagnostic
   moves to the store; struct assumption; check cost (rounds over the
   call graph). Open question 1 and Goose item 5 belong there.

## Major

3. Lines 48-49 "not new policy" vs lines 22-26 (design M1, style 6):
   call it a compiler bug against 3.2/3.6 with evidence, or a
   behaviour change. Note: design M1/B2 read it as direct recursion
   becoming refused; the draft means mutual becoming allowed: wording
   is ambiguous (also Stage 6 #1).
4. Lines 33-41 diverge from Goose without saying so (design M2): Goose
   errors at the call when a back edge passes another pool; the draft
   refuses only at a store. Say which rule ris follows for growable
   handles the cycle grows but never stores into.
5. "Inside a cycle" undefined for callees (design M3; Stage 6 #4): the
   example's store is in `node`, not a member. Define by roots, as
   Goose does; a member's stores before its cycle call count too.
6. Refused examples (design M4, structural 4): `"#{d}"` is already
   refused by 3.2/1.9 without recursion. Add the case the rule exists
   for (activation N stores its local into storage from N-1's local)
   and the back-edge case as code with the diagnostic.
7. Callbacks and captured locals (design M5): an enclosing non-cycle
   def's captured locals are rooted outside (Goose 2705-2710); add as a
   root or a non-goal.
8. Narrower than Goose (design M6; Stage 5 Nit 2): second-tier roots
   (`rest(c, c.nodes.push(...))`) not adopted: say so. Goose §7.8(d):
   a call result built in place into storage the cycle grows: does 2.2
   cover it?
9. Proposed text one dense sentence chain (style 1, structural 5,
   design N1; Stage 5 M1, Stage 6 #2): split into call rule and store
   rule; define "passed-on parameter" with "that"; "a parameter to
   which a back edge passes different storage".

## Nit

10. Line 30-32 "no ... is live, nor ..." (style 2).
11. Line 19 "which is exactly that" (style 3); line 25-26 "gives the
    answer both ways" (style 4).
12. Lines 45-47 term mismatch "passed on unchanged" vs "passed in";
    "nothing Goose bans is lost" reads backwards (style 5); does a
    String parameter count as growing (design N2)?
13. Line 69 unused `b` (all three).
14. Line 56 code block without language tag (structural 6).
15. Struct receiver: value copy vs alias; limit text to class
    receivers (design N4, structural 8).
