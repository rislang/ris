# EGM Stage 8: Intermediate Zoom Out report

Target: doc/drafts/spec-3.5-cycle-roots.md. Verdict: pass with changes.
0 Blocker, 3 Major, 3 Nit. Still fixes the root problem with no new
mechanism; the risk is that earlier stages make it grow.

## Major

1. Critic Blockers 1-2 (alternatives, goals, risks) are too big for a
   one-bullet SPEC change: downgrade to Major and meet them with a
   3-5 line "Decisions" list: refuse at the store, not the call;
   a replaced back-edge parameter stays refused (Goose item 5, closes
   open question 1); second-tier roots not adopted; no `recursive`
   annotation, cycles come from the call graph (3.4); "owner" is
   whatever 2.1 says. Drop the check-cost risk.
2. Not every request becomes rule text: two short rules (3.5 calls,
   3.5a stores) plus a 3-4 line glossary (cycle, back edge, callbacks,
   membership via 3.4). Define "inside a cycle" by roots, which covers
   the `node` callee; captured locals of an enclosing non-cycle def
   are one more outside root.
3. Examples: one allowed (drop `b`), two refused as code with the
   diagnostic (activation N stores its local into storage from N-1's
   local; a back edge passes a local Array for the parameter). Direct
   recursion: one sentence "checked the same way".

## Nit

4. One sentence: the mutual-recursion refusal is a bug against
   3.2/3.6; both forms are allowed.
5. Line 35 "slice" -> "view".
6. Remove open questions: Q1 closed by Decisions; Q2 belongs to 2.1,
   text limited to class receivers.
