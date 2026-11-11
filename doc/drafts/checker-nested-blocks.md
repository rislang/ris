# Draft: linear-time checking of nested blocks

Second draft, 2026-11-10, after the EGM review (design, codebase
details, implementation readiness). Code is cited by method name in
src/compiler/iyi/semantic/tape_shrink_checker.cr.

## Problem

The checker walks a loop or block body in `loop_value`. It repeats the
body until the entry state settles (the settling rounds, at least one),
then runs two final rounds whose events it keeps. Round 2 exists so
that its uses are checked against round 1's shrinks: a view carried
into the next round and read there after round 1's `clear` is refused.
Each round re-walks every inner block in full, so a body d blocks
deep is walked 3^d to 4^d times, and 2^d copies of its events are kept.

Uses and shrinks go into two flat lists, `@uses` and `@shrinks`; the
end of `check` pairs every shrink with every later use. A use at index
i conflicts with shrink s when i >= s.at, i < s.last_use (if set), the
use's and shrink's guards are compatible, and one of the use's views
has born <= s.at, compatible guards, a root in s.roots, and is not an
index view of a growth shrink. A growth shrink is judged only if one
of its roots passes the growth filter (`@pooled_roots`, parameter
roots of Array type). Only that pass and `loop_env`'s cap read `born`.

Measured (release compiler on minitest, `build --no-codegen`), a chain
of d nested `step(x) do |v| ... end` blocks: d=8 13 s, d=9 60 s,
d=10 265 s, about 4.5x per level. web's examples/testing_test.ri
checks for 1182 s, web/static_test.ri for 11 min.

## Design

Two changes in `loop_value`, nothing else; no summaries are replayed
and no positions are renumbered.

### 1. A settling walk walks inner bodies once

A settling round's events are dropped and only its environment is
kept. While any loop is settling (a depth counter, restored in an
`ensure`), an inner `loop_value` walks its body once from
`loop_env(env, start)`, joins the round into that entry and returns:
no settling, no final round.

Why the settled state is still reached: every variable a body binds,
the inner body's too, is joined into the outer environment, so the
outer settling loop runs until one walk of each inner body adds
nothing. That is the inner fixpoint as well. Each inner loop then
settles again in full, from that state, in its own final walk below.
Refusals raised during a walk (`refuse`) are raised again there.

Cost: a settling walk of a body costs its text size; a loop k deep
settles in about d - k + 2 rounds.

### 2. One final round, and round 2's pairs from it

Only one final round R1 is walked. Before it the checker:

* appends an empty marker use at position a, so every view made in R1
  is born after a;
* gives every view of the entry state a mark: a negative `born`, one
  per (variable or slot, view), remembering its source and its real
  `born`. A negative `born` is <= every position, as the capped one
  was, so R1 pairs exactly as before.

After R1 (uses `[a, b)`), round 2 is derived instead of walked. R2
starts from R1's end state E and takes the same walk, so a use u in R1
reads in R2:

* for a marked view from source x: the views of E at x (a marked one
  standing for its real `born`);
* a view born <= a (made before the loop) unchanged;
* nothing for a view made in R1: in R2 it is made again, after R1's
  shrinks, so it pairs only with R2's copies of them, as in R1.

Every R1 shrink s without a `last_use` (one set inside R1 ends before
R2) is paired with these derived uses by the rule above. A conflict is
not raised at once: the (shrink, derived use) pair is kept and judged
in the final pass with the growth filter, right after s's own uses, so
the message and its order stay as they were.

Then every mark is replaced by its real `born` in R1's uses, the end
state, the result and `@returns`/`@kept_returns`. A mark left elsewhere
only refuses more, never less. The state after the loop is
`join_env(head, E)`: E's views made in R1 stand where R2's would, on
the same side of every R1 shrink.

Inner loops keep their own marks; an outer mark seen by an inner loop
is a view from before that loop.

Why this keeps every refusal:

* R1's own pairs, and pairs with shrinks before or after the loop, are
  judged as before: R1 is the same walk with the same `born` order.
* R2's uses are R1's uses read from E; their partners among R1's
  shrinks are kept as pairs. A view made in R2 is born after every R1
  shrink, so it has no R1 partner; its R2 partners mirror R1's.
* After the loop, a use pairs with an R1 shrink where it paired with
  the R2 copy: views carried round to round are also in `head`, born
  <= a.

Events: each loop keeps one round, so the event count and the final
pass grow with the text, not 2^d. The derived pairs cost
(uses x shrinks) of R1 per loop, and only conflicts are kept.

## Answers to the review

* Renumbering (Blocker): dropped; nothing is removed or moved.
* Growth filter judged early (Major): pairs are kept and judged at
  the end.
* Part 1 in settling rounds (Major): settling rounds keep no events.
* Replay audit and key equality (Blocker, Major): no replay, no keys.
* Solve phase: `solve` uses the same `loop_value`, so it gains too.
* `RIS_CHECK_STATS`: not added; the gate times a 16-deep chain under
  a timeout that the old cost misses by hours.

## Gate

* test/ris/nested_blocks_depth.ri: 16 nested blocks, each binding a
  local and appending to an outer Array; check.sh builds and runs it
  under a 60 s timeout and compares its output.
* test/ris/refused/nested_clear_deep.ri: a deep chain with a loop
  that reads a view taken in the previous round after the round's
  `clear`; expected `shrink tape storage with a live view`.
* All refused programs and check.sh pass unchanged.
* web's two tests: times before and after in the commit body.
