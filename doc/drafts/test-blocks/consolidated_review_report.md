# EGM review: test blocks in module files

Verdict: not ready; fix 2 blockers and the majors before SPEC or code.

Target: `doc/drafts/test-blocks/test-blocks.md` (lines 1-252).
Section 2 (D1-D4) is the user's decision; only its wording is reviewed.

## Reviewer status

| Reviewer | Status |
| --- | --- |
| codebase-details | completed |
| design | completed |
| implementation-readiness | completed |
| zoom-out | completed |

## Blocker

B-1. Where a block sits and what "module scope" is (25-31, 61-68,
104-107). `ris init` writes a `module NAME ... end` body (init.cr:162);
D1's example calls `Store.slugify` qualified, so the block seems to sit
after `end`, yet 4.3 compiles it "in the module's own scope". Fix: say
whether blocks are inside the module body or after it, and derive the
scope rule from that, before step 3.

B-2. `test "x"` NEWLINE already parses as a call (67-73). With `test`
an ordinary identifier, a user's top-level `test "x"` call or a
`def test(name)` silently changes meaning. Undefined: `do` on the next
line, `test("x")` NEWLINE, `test "x", opt`, body starting with `do`.
Fix: write the exact grammar (`test` STRING NEWLINE, nothing else),
reserve `test` in declaration position at module top level, give the
error for every other shape; add the cases to step 3's gate.

## Major

M-1. `todo` in a block ends the whole program (144-146). `todo` is
`NoReturn` and calls `exit 77` (prelude.iyi:2442); later blocks never
run, earlier failures are lost; IyiTestCases records only pass/fail.
Fix: name the runtime change (todo records the block in IyiTestCases,
ends only it; verdict picks 77); add to step 4 and its gate.

M-2. Top-level statements in the test program (140, 241-243). 4.5
states they run; Q1 still asks. A module calling `listen` never reaches
its blocks; init's module prints "hello from demo" into the result
stream. Fix: settle Q1 before step 3: either refuse blocks in a file
with top-level statements ("move the code into a def") or never run
them, and say so in SPEC.

M-3. "One file set" cannot serve both verbs (151-159). `ris spec` reads
every .ri/.iyi/.cr/.sh/.py under test/ (spec-cli.md:78-79); `ris test`
builds only `*_test.{ri,iyi}`. Fix: one shared walk (root, exclusions,
block scan) with a per-verb filter.

M-4. The scan runs test/cli fixtures (155-159). Steps 3-6 add fixtures
with failing or todo blocks; a ROOT-wide scan runs them and counts their
tags. Fix: exclude fixture dirs explicitly; gate that a failing fixture
block is not run.

M-5. Block identity `file:line "description"` churns (142, 176-177).
Any edit above a block moves it, so acked tags go stale. Fix: key on
file plus description (unique per 4.1); keep line only in reports.

M-6. `ris spec ack` on blocks underspecified (174-180). spec-cli says
ack inserts at the top of the leading block, which 4.7 refuses in a
module file; "stale" (227) is undefined for blocks; no output/JSON
shape. Fix: ack edits only an existing tag above `test`, never inserts;
give an output example.

M-7. Test helpers can shadow module defs (91-93, 104-107). A
`private def slugify` in the section overloads or replaces the code
under test, only in the test build. Fix: refuse a helper whose name and
arity match a module def; say if private types/constants are allowed
and that code above cannot call helpers.

M-8. Test program output contract missing (133-146). Open: path base
of `file:line`, totals across several module programs, what
`ris test path/store.ri` does (test.cr:110-112 treats any file as a
program), a block with both a failure and a todo. Fix: specify each;
add the module-file argument to step 4's gate.

M-9. Step order (213-215 vs 226). Step 1's gate needs a tagged block,
which exists only after steps 3 and 6. Fix: step 1 does B1 and the
shared list only; move B2 to step 6.

M-10. Scope: split unrelated fixes and trim 4.9 (164-168, 182-203,
228). B1 and the 4.8 `ris init` header are bugs today, independent of
blocks; LSP and `--affected` are separate features; "Gate per tool" is
not checkable. Fix: ship B1 and 4.8 as own commits and point to them;
keep formatter and `ris doc` with concrete gates in step 3; move LSP
and `--affected` to section 8, or give each a concrete gate.

M-11. Init header would hide the spec tag (184-190, 216). init writes
`# spec: 1.1@VERSION` then `todo` (init.cr:198-202); putting `module`
first pushes the tag out of the leading comment block, losing 1.1's
coverage. Fix: tag first, header below (check the parser allows it), or
widen the reader; add "ris spec still sees 1.1" to step 2's gate.

## Minor

m-1. B1 citation (166-168): the `.ri` glob is test.cr:109, the root `.`
comes from line 92. Cite "test.cr:92, 107-109"; default root becomes
ROOT (spec-cli 4.1).

m-2. Lexer scan cannot see top level (155-157): heredocs, macros and
`test "x" do` match. Make it a candidate filter; the parse decides; only
lines ending after the string count.

m-3. Cycles (126-129): no need shown. Either refuse a cyclic test-only
import with a named fix, or state that B resolves against M's metadata
without tests and the init order.

m-4. `ris build` never type-checks blocks (116-118): say it is
intended, or have `ris check` check the sections.

m-5. Step 5 gate unobservable (224-225): name the check, e.g. a std/dir
symbol absent from the binary or from export metadata.

m-6. wasm32 behaviour (137-139) has no gate: add one or mark untested.

m-7. One binary per module may not scale (133-139, 249-251): time it
on blog-demo, or note it as the cache draft's trigger.

m-8. Newcomer terms: tape, R-1, exit 77, task-per-case, spec-cli 4.1
(44, 118, 137-148, 161). Add a few words or a link each.

m-9. D1-D4 wording: D3 "right above" vs 4.7 "directly above": use one
phrase. D3 "the unit is the block, beside today's whole-file tags" could
read "a tagged block counts as one test, as a tagged file under test/
does today". D1 "(Who enforces it: 4.2.)" could read "(The compiler
enforces it: 4.2.)".

Not checked: the draft's quotes from Koja TESTING.md and iyi SPEC
(lines 7, 12, 106, 113).
