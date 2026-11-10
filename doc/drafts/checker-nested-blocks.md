# Draft: linear-time checking of nested blocks

First draft, 2026-11-10, before any implementation; not yet reviewed
by EGM. Code citations are tape_shrink_checker.cr at 2138039be
(src/compiler/iyi/semantic/).

## Problem

The checker walks a loop or block body in `loop_value` (:1563): it
repeats the body until the entry state settles (at least two rounds),
then runs two final rounds (:1603) whose events it keeps. Round 2
exists so that its uses are checked against round 1's shrinks: a view
read in round 2 after round 1's `clear` is refused. Each round re-walks
every inner block in full, so a body nested d blocks deep is walked
at least 4^d times, and 2^d copies of its events are kept.

Uses and shrinks are not judged as they are recorded. They go into
two flat lists, `@uses` and `@shrinks`, and the end of `check`
(:1436-1460) pairs every shrink with every later use: a use at index
i conflicts with shrink s when i >= s.at, i < s.last_use (if set),
guards are compatible, and one of the use's views has
`born <= s.at` and a root in `s.roots`. That pass is quadratic in the
event count.

Measured (debug compiler, `build --no-codegen`): a 10-deep chain of
`step(x) do |v| ... end` takes 7.4 s, about doubling per level. web's
examples/testing_test.ri (about 10 deep) checks for 1182 s,
web/static_test.ri for 11 min.

Caching each block's settled state per entry removes only the settling
rounds' share (tried, reverted): the two final rounds still double the
work and the events per level. Linear cost needs four parts together.

## 1. Per-loop cross-round check, then drop round 1

When a loop's two final rounds R1 (uses `[a, b)` of `@uses`) and R2
(`[b, c)`) end, the checker judges R1's events itself and removes them.

Checked at the loop's end, with the same rule and message as :1446:

* every use in R1 against every shrink recorded so far (all shrinks
  before the loop, and R1's own);
* every shrink in R1 against every use in R2.

Then it removes R1's uses and shrinks, and renumbers every position at
or after b down by `b - a` (shrink `at`, `last_use`, view `born`, in
`@uses`, `@shrinks`, the environment and pending values). A position
inside `[a, b)` becomes a.

Why this keeps every refusal (the final pass sees the rest):

* *R1 uses lose no partner.* A use pairs only with shrinks at or
  before it, and those are all recorded when R1 ends: shrinks are
  appended in walk order. A `last_use` set later by `leave_branch`
  (:802) is at or after the branch's end, so it never cuts R1 off from
  a shrink before the branch.
* *R1 shrinks lose no partner.* Their partners are uses in R1 (judged
  above), in R2 (judged above) or after the loop. For a use after the
  loop, R2 holds the same shrink node, s2, with `s2.at > s1.at`; every
  view with `born <= s1.at` also has `born <= s2.at`, so s2 refuses
  whatever s1 would, provided s2's roots contain s1's and its guards
  are no narrower. Where no such s2 exists (R2 took another branch, or
  rebound the shrunk local), s1 is kept, moved to position a.
* *Renumbering changes no answer.* A view born inside R1 gets
  born = a. Only shrinks with `at` in `[a, b)` could tell a and its
  old position apart, and those are removed or moved to a, where
  `born <= at` holds exactly as before for views born before them.

Open: the growth filter at :1439 reads `@pooled_roots`, parameter
roots and root types that may be filled later in the walk. Judged at
the loop's end it may see less. Either keep R1's uses that view a
growth shrink's roots until the final pass, or show that those sets
are complete before the first loop is walked.

## 2. A loop's summary per entry, replayed

Within one outermost loop, the checker records for each
(inner body, key) what its `loop_value` produced:

* its result `Value` and its effect on the environment (the joined
  vars and slots);
* its events after part 1, as offsets from its `start`;
* what it merged into `@returns` and `@kept_returns`.

When the same body is reached again with an equal key, the checker
replays that summary instead of walking: it appends the events
shifted to the current `@uses.size`, applies the environment effect
and merges the returns. With part 1, each body is walked a bounded
number of times per distinct key, and each loop keeps one round's
events, so the work grows with the program text, not with 2^d.

The record lives for one outermost `loop_value`: callee summaries do
not change inside it (they are fixed per pass of the call graph), so
a stale record cannot be read. The depth counter is restored in an
`ensure`, so a raised refusal cannot leave it wrong.

Replay does not repeat refusals: a refusal raises during the first
walk, before any record is made. Under `RIS_SCOPE_ERRORS=all` the
first walk lists it once, which is enough.

Every other side effect of a walk must be safe to skip on replay: it
is keyed by an AST node or root id that the first walk set already,
or is a set union. Open: audit the ~60 instance variables;
`@dead`, `@root_scopes`, `@root_tapes`, `@unproved` and
`@first_refusal` first.

## 3. A key relative to the loop's start

`loop_env(env, start)` (:1545) caps every view's `born` at `start`,
an absolute position, so a body entered at another position never
matches a record. The key stores each `born` as `start - born`, an
offset back from the entry. Replay maps offsets back with the current
start: pairing with shrinks before the loop then uses the true
positions, because the final pass reads absolute values only after
the mapping.

The key also holds the state a walk reads besides the environment:
`@guards`, `@loop_storage`, `@condition_storage`, `@scopes`,
`@tape_blocks`, `@checking`, `@text_only`, and the loop's `kind` and
condition node.

## 4. Merging repeated shrinks

Replay and part 1 can leave runs of shrinks from the same node with
no use between them. Two shrinks with the same node, roots, guards and
growth flag, and no use between their positions, pair with exactly the
same uses; the later one also covers every view the earlier does
(`born <= at` holds for a larger `at`). Keep the later one. Shrinks
with a use between them are both kept: the earlier one alone pairs
with that use.

## Gate

* test/ris/nested_blocks_depth.ri: a chain of 16 nested blocks,
  each binding a local and appending to an outer Array; it must build
  and print its known output under `timeout 120` in check.sh. Today it
  does not finish.
* A structural counter, not a timing: `RIS_CHECK_STATS=1` prints how
  many times `loop_value` walked a body. The gate expects at most
  8 x 16 walks for the 16-deep chain, so a return of the exponential
  cost fails in any load.
* test/ris/refused/nested_clear_deep.ri: the same chain with a
  `clear` at depth 8 and a view taken before it read at depth 12 in
  the next round; expected message `shrink tape storage with a live
  view`. It checks that part 1 still pairs across rounds deep inside.
* All existing refused programs and check.sh pass unchanged.
* Before and after times for web's two tests in the commit body.

## Open questions for review

1. The growth filter judged at the loop's end (part 1, last item).
2. Whether R2's shrink always dominates R1's (same node, roots
   containing R1's) or the fallback that keeps s1 is common enough to
   matter for cost.
3. Which side effects replay may skip (part 2's audit).
4. Whether a key equal under `==` of `Env` is cheap enough: each
   comparison walks every variable; a hash of the key may be needed.
5. Whether `RIS_CHECK_STATS` belongs with `RIS_TAPE_STATS` in
   SPEC 6.6 or stays a compiler debug switch.
