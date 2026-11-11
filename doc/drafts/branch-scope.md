# Is a branch a scope?

Draft, 2026-11-10. Status: for EGM review. No SPEC or code change yet.

## Problem

SPEC 1.1 names the scopes that free scratch: "Every def, loop round and
block frees its scratch when it ends". A branch (`if`, `unless`, `case`
arm, `else`) is not among them.

SPEC 3.2 adds: "Branch-local and temporary storage cannot escape". The
checker reads this literally: tape_shrink_checker.cr pushes a scope per
branch (`@scopes << node.then.object_id`, near line 2600). So an object
made under an `if` and stored into an outer Array is refused, while the
same code without the `if` passes. The runtime frees nothing at the end
of a branch, so the refusal guards no real lifetime.

Commit f14f639ab ("Checker: a branch is no scope") stopped pushing the
branch scope, added test/ris/branch_store.ri (passes) and
test/ris/refused/round_store.ri (store from a loop round, refused). It
broke test/ris/refused/root_branch_escape.ri and root_store_join.ri and
was reverted in 8f92c108f.

This blocks HTTPClient pooling (TODO.md section 4): a pool makes a
connection only when none is free, i.e. under an `if`, and keeps it in
an outer Array.

## The two refused tests

* root_branch_escape.ri: an owner made in the `then` arm; its finished
  String is the `if`'s value, read after the `if` in the same block.
  The owner lives on the block's tape until the block ends, so the read
  is safe. The refusal is an artefact of the branch scope.
* root_store_join.ri: a String from a branch-local owner is stored into
  a holder that may be `left` (outer) via a join. Same scope again: both
  live until the `tape` block ends. Safe at runtime.

Both tests encode the rule we propose to drop, not a real escape.

## Options

A. A branch is not a scope. Reword 3.2 so escape is judged against the
   enclosing def, loop round or block. Restore f14f639ab. Rewrite the
   two refused tests so the source sits in a loop round (or nested
   block) and the destination outside it: they stay refused for a real
   reason. Add their present forms as passing tests.
B. Keep 3.2. Callers make the owner before the `if`. Costs an object
   per call even when unused, defeats pooling, and the error gives an
   agent a rule that 1.1 contradicts.
C. Make branches runtime scopes that free scratch at their end. A new
   tape mark per branch: cost on every `if`, and a value computed in a
   branch (the `if`'s result) would need a copy out. Large change to 1.1
   for no known gain.

## Recommendation: A

It aligns the checker with 1.1 and the runtime, removes a false
refusal, and needs no runtime change. An agent writes the natural code.

Proposed SPEC 3.2 (replacing its third sentence):

> Storage made in a def, loop round or block cannot escape it; a branch
> is not a scope, so its storage lives to the end of the enclosing one.
> Loops see earlier rounds.

Proposed SPEC_CHANGELOG entry:

> 2026-11-xx, 3.2: a branch is no scope. Escape is judged against the
> enclosing def, loop round or block, the scopes 1.1 frees. Reason: the
> runtime frees nothing at a branch's end; the old rule refused safe
> code (an object made under `if` kept in an outer Array) and blocked
> HTTPClient pooling.

## Tests to change

* test/ris/branch_store.ri: new, passes (from f14f639ab).
* test/ris/refused/round_store.ri: new, refused (from f14f639ab).
* refused/root_branch_escape.ri: move the owner into a `loop`/`each`
  round whose result is read after the loop; keep refused. Old form
  becomes test/ris/root_branch_value.ri, passing.
* refused/root_store_join.ri: make `right` and the owner round-local,
  destination joined with an outer holder; keep refused. Old form
  becomes a passing test.
* Check refused/owner_shrink_branch.ri, shrink_loop_branch.ri,
  recursion_branch_pending.ri still refuse for their stated reason.
* test/ris/check.sh: list the new files.

## Risks

* Branch inside a loop round: the branch's storage belongs to the
  round; storing it into an owner outside the loop must stay refused.
  round_store.ri must cover the `if`-in-round form, not only a bare
  round.
* Views from the branch: a view of branch-made bytes read after the
  `if` is now accepted; 3.3 (shrink/clear with live views) must still
  see the view, since join tracking (3.1) keeps every alternative.
* Guards and nil narrowing: `if x = make` / `x || make` create storage
  in the condition or a short-circuit arm. They must follow the same
  rule; one test each.
* `case`/`unless`/ternary/`&&`/`||` arms: confirm the checker pushed no
  other branch-like scope; all must behave as `if`.
* `while`/`until` body is a loop round, not a branch: must keep its
  scope. Rescue/ensure arms: decide (proposal: not scopes, as branches).
* Fibers/blocks passed to calls stay scopes: unchanged.

## Out of scope

Runtime freeing (option C); any 1.1 change.
