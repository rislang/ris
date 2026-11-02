# EGM Stage 5: Zoom Out report

Target: doc/drafts/speed-plan.md (= TODO.md "## Speed", uncommitted).
Verdict: revise. 1 Blocker, 3 Major, 4 Nit.

## Blocker

B1. Bullet 1, "decide by an allow list", reinvents an existing
analysis. The normalizer wraps every def, while and block in
`__iyi_scope_mark(true)`; TapeScopeChecker#run/#off
(src/compiler/iyi/semantic/tape_scope_checker.cr:141-152) turns the
flag off unless TapeCallGraph#allocates? (tape_call_graph.cr:157,
Effects visitor) says the body allocates. Verified by the Elephant.
So the question is why Effects calls the scan_string and skip_spaces
rounds allocating. Likely cause (not verified): jqg.ri:1178-1186, a
`return text[start, p - start]` in an If branch; Effects#visit(If)
counts the branch, though a return leaves through the def's result,
not the round's reset. Fix: "find what makes allocates? true in these
loops and refine Effects"; keep the IR gates; drop the allow list.

## Major

M1. "Goose implementation C.2" is the wrong cite: the watermark rule
is in implementation.md 6.2 (Stack assignment) and goose_spec C.1.
M2. Order contradicts AGENTS.md: TODO says time at each step end now,
AGENTS.md says measurement is off until later. Change AGENTS.md now to
the baseline rule; defer only optimization work.
M3. Bullet 2 (fast path for rounds that make something) has no perf
number behind it; Goose 6.10's reason is C aliasing, not LLVM IR; "one
store" skips __iyi_scope_reset's side check (tape.iyi:2387-2400).
Make it conditional on perf after bullet 1, or drop it.

## Nit

N1. iyi has the same FNV (../iyi/src/iyi/string.iyi:408-411): say
"list it in UPSTREAM.md" plainly.
N2. Cite Goose's hash: doc/reference/goose/docs/stdlib.md, Hashing.
The "multiply and rotate" detail is not in the snapshot.
N3. Hash bullet is low-level but each detail maps to a gate; the
low-bit spread is right (hash_tape.iyi:165-175 masks low bits).
N4. Draft is already in TODO.md's working tree: commit after fixes.
