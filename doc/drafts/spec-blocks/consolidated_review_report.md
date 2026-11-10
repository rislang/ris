# EGM review: spec-blocks.md

Verdict: REVISE. 2 Blockers, 10 Majors, 8 Minors. D1-D10 not reopened;
fix B-1, B-2 and the Majors before SPEC.md or code changes.

Target: doc/drafts/spec-blocks/spec-blocks.md (whole file)

## Reviewer status

| Reviewer                 | Status    |
| ------------------------ | --------- |
| design                   | completed |
| implementation-readiness | completed |
| zoom-out                 | completed |
| codebase-details         | completed |
| comprehension            | completed |
| structural               | completed |
| style                    | completed |

design and implementation-readiness did not read SPEC.md or spec-cli;
codebase-details and zoom-out did, and cover that ground.

## Blockers

B-1. 5.10, 5.13 (D7): SPEC_CHANGELOG check unaddressed. Today
spec_check (spec_clauses.cr:575-578) fails a clause without a
changelog entry `N.M@HASH`; ris init writes that heading. The draft
drops `@VERSION` but never says whether the changelog check stays.
Fix: in 5.10 state that the lock hash is spec-cli 4.2's version (SHA-256
of normalized clause text, 8 hex) and that changelog headings keep
`N.M@HASH` taken from it, or that the check is dropped. Match 5.11.

B-2. 5.10, step 6 gate: old `@V` tags contradict themselves. ack "leaves
the tag alone", but spec_check (lines 569-572) fails a tag whose
version differs, so a reviewed clause never clears.
Fix: once spec.lock holds a line for N.M, ignore the version in an old
`# spec: N.M@V` tag; say so in 5.10 and in the step 6 gate.

## Majors

M-1. 5.10: hash input undefined (with B-1). Clause extent, nested
N.M.K text, whitespace and markdown handling, algorithm and length
are unstated; no rule for orphan lock lines.
Fix: text runs from `N.M ` to the next clause or heading, children
excluded, whitespace collapsed; SHA-256, first 8 hex. `ris check spec`
reports orphan lines; `ris spec ack` removes them.

M-2. 5.10, step 6: turning the check on reddens existing projects.
Every clause with proofs but no lock line fails; nothing seeds the
lock from today's `@V` tags.
Fix: step 6 seeds spec.lock from existing tags (e.g. `ris spec ack
--from-tags`); gate: ris's own `ris check spec` green after seeding.

M-3. 4.5, 4.2 "(7.2)", 5.8: clause states undefined and contradictory.
There is no 7.2; kept/missing/todo/broken are not defined; `ris spec`
shows 1.2 `kept` while `ris test` shows `FAIL 1.2`. Today `ris spec`
reads tags only (SPEC_STATUSES, line 394) and section 3 rules out a
result cache, so it cannot know pass/fail.
Fix: add 5.14 "Clause state": `ris spec` reports coverage from tags
and blocks (covered/todo/uncovered/to review, mapped from today's
names); pass/broken comes only from `ris test`. Fix 4.5 and line 150.

M-4. D6, 5.5, 5.7: "top-level code" of a program file undefined.
Unclear whether constants, type defs and imports beside `run(...)`
stay, and what a def using a dropped value does.
Fix: list kept nodes (import, def, type, constant declarations);
drop all other top-level statements; a def referring to dropped code
is a compile error with a fix message.

M-5. 5.1, `test "x"` refusal vs D8/D9. Refusing it at any top-level
line breaks today's `*_test.ri` programs, which D8 and D9 keep.
Fix: refuse `test "x"` only in a file with a spec section until
step 8; refuse everywhere after.

M-6. 5.2: Bool-line lowering unspecified. No pass, runtime call or
carrier of line text and both sides; how `assert` (which panics)
fits beside "a failed line does not stop the block"; Bool? and
unions not covered.
Fix: name the rewrite, e.g. `a OP b` ->
`__ris_spec_check(a, b, "OP", text, file, line)`, recording without
panic, and the pass that does it. Only static type exactly `Bool`
asserts; `Bool?` refused with fix "write `x == true`". `assert` in
a nested body panics: block broken.

M-7. 5.8: execution model split and vague. "a task of its own" does
not say sequential; wasm32 "first broken or todo ends the program"
contradicts D2 (todo ends only its block) and 5.2.
Fix: blocks run one after another, each awaited; failed lines and
todo are recorded per block on every target; only a panic differs on
wasm32 (ends the program, reported against its block).

M-8. 5.8 vs test.cr:363: CLI-to-compiler interface missing. Today
run_one_test shells out to `build FILE -o`.
Fix: name the replacement (e.g. `build --spec FILE`), the per-block
`--json` record (clause, ordinal, file:line, status, output), and how
`--timeout` applies to a module with many blocks.

M-9. 5.7, 5.11, Q2: RisProgram API incomplete and HTTP-only. `request`
has no signature; return type and non-2xx behaviour unstated; init's
demo is a CLI program but `run` is open in Q2 and called with no args.
Fix: give typed signatures; the port wait applies only to
get/post/request; `run(args = [] of String, stdin = "")` waits for
exit. Until Q2 is answered, 5.11 writes the `todo` form only.

M-10. 5.11, header (init.cr:161), 5.9: claims do not match code.
init.cr:161 is the heredoc, not the module grammar; init's
demo_test.ri has no import (lines 198-202) so nothing "fails"; real
clause text is "Running demo.ri prints `hello from demo`." (line 171);
init also writes SPEC_CHANGELOG.md and AGENTS.md (lines 215-218 teach
`# spec:` tags). spec_walk takes any .ri/.iyi/.cr/.sh/.py under test/
and skips symlinks; test.cr globs both suffixes, any case.
Fix: cite the parser rule for `module PATH`; describe init's real
output and list AGENTS.md, SPEC_CHANGELOG.md and usage text (lines
223-234) as changing; state the shared walk's match, case and
symlink rules and keep test.cr's miscased-name refusal (line 121).

## Minors

m-1. 4.5, 5.8 line 376: "9 blocks: 7 ok" but 4.2-4.4 hold 8 blocks.
Fix: "3 modules, 8 blocks: 6 ok, 1 broken, 1 todo" in both places.

m-2. 4.1, 4.5: excerpt lacks the `* ` bullet spec-cli 4.2 requires;
1.3 is listed `missing` but absent from 4.1.
Fix: write clauses as `* 1.1 ...`; add 1.3 to the excerpt and note
the excerpt is partial.

m-3. 4.3 line 162: `answer.body ~ "title"` uses `~`, still open in Q2.
Fix: use `answer.body.includes?("title")`, or mark "assumes Q2".

m-4. 4.5 line 200: the `todo` row sits under `proofs`, not `state`.
Fix: align `todo` under the state column.

m-5. AGENTS.md lines 42-45 and spec-cli 6.7-6.9 still teach
`# spec: N.M@VERSION` tags and test/spec/; no step updates them.
Fix: add these edits to step 6's work and gate.

m-6. 5.3, 5.8 vs testing.iyi: IyiTestCases.verdict (line 201) knows
only 0 and 1; `todo`/exit 77 lives elsewhere.
Fix: name the file defining `todo` today; say the verdict gains a
todo count.

m-7. 5.12, step 7: `--affected` and LSP hover are not needed by D1-D9
(D10: later work in section 9).
Fix: move them to section 9; keep formatter and `ris doc`.

m-8. Wording and placement: ROOT used (D7, 5.1) before its definition
in 5.9; "TMPDIR and HOME (the temp directory)" ambiguous; "SPEC 1.1"
in 5.8 ambiguous; "The rule is simple and" (5.2) adds nothing; the
gate in 5.11 belongs in step 7; 5.13 says "5.1 to 5.10" but 5.11 and
5.12 are user-visible.
Fix: define ROOT at first use; "both set to the block's temp
directory"; "ris SPEC.md 1.1"; delete the phrase; move the gate;
write "5.1 to 5.12" or say why 5.11-5.12 are left out.
