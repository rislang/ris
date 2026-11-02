# EGM Stage 5: Zoom Out report

Target: doc/drafts/spec-3.5-cycle-roots.md. Verdict: pass with changes.
0 Blocker, 2 Major, 4 Nit. Root problem fixed, not a symptom; no new
mechanism; tied to Goose §7.8.

## Major

1. Proposed 3.5 (lines 30-41) packs two rules into one ~12-line bullet:
   (a) what may be live at a call into a cycle, (b) the cycle store
   rule. Goose keeps them as separate paragraphs. Split (3.5 calls,
   e.g. 3.5a stores) and state once that "passed on unchanged" serves
   both.
2. Open question 2 (lines 90-91), @[OnTape] struct as owner, is a 2.1
   question. Say 3.5 applies to whatever 2.1 calls an owner and move
   the question out.

## Nit

1. Open question 1 (lines 87-89): close it. Record the conservative
   choice (refused at the store) as the decision, point at Goose's
   future-work item 5.
2. The draft is stricter than Goose §7.8 (lines 2729-2738: a parameter
   whose argument is read through a passed-on parameter or pool,
   `rest(c, c.nodes.push(...))`). Say under "Changes in meaning" that
   this refinement is not adopted yet.
3. Examples: add a direct `pipe -> pipe` case or note it behaves the
   same; give the back-edge refusal as code; `b = other(d + 1)` never
   uses `b`: drop the assignment or say why.
4. Line 35 "slice": SPEC says "views". Use SPEC's term.
