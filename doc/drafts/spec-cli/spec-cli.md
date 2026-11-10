# Draft: `ris spec`, linking SPEC.md clauses to the tests that prove them

Status: amended after EGM review
([consolidated_review_report.md](consolidated_review_report.md)) and the
user's decisions ([decisions.md](decisions.md); "Confirmed later" wins).
This draft is the single design record of the tool.

Context: ris is iyi plus Goose's tape memory (AGENTS.md). A gate is a
pass/fail script in test/cli/. `ris check` is the one "is the work done"
verb; `ris check test` is its part that runs `ris test` (every
`*_test.ri`). blog-demo is a sample program written by an agent.

## 1. Problem

An agent reports "done", `ris check` is green, and the program still
fails the first time a person runs it (blog-demo: "Cannot create
directory: posts"). Green means "nothing broke", not "what was promised
is done", because nothing ties a test to a promise.

ris writes promises down: SPEC.md has numbered clauses (`* 1.1 ...`).
62 test files cite them in prose ("SPEC 5.1"), but no tool reads that:
a clause can have no test, a test can cite a missing clause, and a
clause can change while its tests keep proving the old text.

## 2. Principle

Spec is intent and the source of truth; tests are its proof; code is
derived. A bug found by hand is a missing clause. SPEC.md holds only
promises (numbered clauses); reasons go to SPEC_CHANGELOG.md, open
questions to a draft, pending decisions to TODO.md, measurements to
test/speed/.

## 3. Goals and non-goals

Goals: every clause names its tests; every test can name its clauses;
a changed clause stops its tests from counting until they are
reviewed; an agent can read one clause instead of the whole spec.
Every clause has a test from the moment it is written; work not done
is a `todo` test, so the unfinished promises are the todo tests.

Non-goals: one new test outcome, no new framework (`ris test` stays);
no issues or commits in tags; no spec language beyond numbered
markdown bullets; no git use at all; TODO.md stays for work that is
not a promise. Future work: `ris start N.M "..."` writes a failing
tagged test.

## 4. Design

### 4.1 Root and spec files

The root is the nearest directory, from the current one up, holding
`ris.mod` or `iyi.mod`; with none, the current directory when it holds
a spec. The spec is `ROOT/SPEC.md` or every `ROOT/spec/*.md` read in
order of its leading number (`spec/1-storage.md`); either is read,
both present is an error. The clause number is the address, so
splitting the file changes no tag. SPEC_CHANGELOG.md is
`ROOT/SPEC_CHANGELOG.md` in both layouts.

### 4.2 Clause grammar and version

- A chapter heading is a line `## N. Title`.
- A clause starts with a line `* N.M text` (N, M decimal) under the
  heading of chapter N; another N is an error, as is a number seen
  twice. Lines before the first heading are not read.
- Indented non-blank lines continue it; any other line ends it.
- Its text: the first line after the number, then each continuation
  line, joined with spaces; every whitespace run is one space; trimmed.
- Its version: the first 8 hex digits of SHA-256 of that text (UTF-8).
  A reflow keeps the version; any other edit changes it.

Numbering keeps SPEC.md's rule: a new clause goes last in its chapter;
a removed clause leaves its number unused; a tag naming it fails.
AGENTS.md advises splitting a large clause, so a typo fix touches few
tests.

### 4.3 Tests and tags

The scanned set: every file under `ROOT/test/` ending in `.ri`,
`.iyi`, `.cr`, `.sh` or `.py`, hidden directories left out. These use
`#` comments. src/ and std/ citations are not tags. The unit is the
file: whatever it names, it names as a whole.

A tag line is in the file's leading comment block (after an optional
`#!` line and blank lines, the consecutive lines starting with `#`):

    # spec: 1.3@a4f20c19, 1.5@0c19aa01
    # spec: none (implementation test: the parser's cache)

An item is `N.M@hhhhhhhh` or `N.M` (no version yet: "unversioned").
`none (reason)` marks a test that proves no clause on purpose; it
stands alone. Several tag lines add up. Anything else after `spec:` is
an error.

A file with no tag line is read in prose: every full-line `#` comment
matching `SPEC N.M` (not `iyi SPEC`, not `N.M.K`) names N.M,
unversioned. A file with a tag line is not read in prose.

A test naming several clauses counts for each. AGENTS.md advises (not
enforced) one test of its own per clause, so a failure names one
promise; `ris spec N.M` shows own and shared tests.

### 4.4 Todo tests

A promise not yet kept still gets its test at once:

    # spec: 1.3@a4f20c19
    todo "the posts directory is not created yet"

`todo(reason : String) : NoReturn` is in the prelude, on every target
(wasm32 too): it prints `todo: REASON` to stderr and calls `exit 77`
(automake's SKIP code). A file's outcome is fail > todo > pass: `todo`
ends the file. `ris test` reports `FILE: todo` with the reason; text
counts `N passed, M failed, K todo`; JSON adds `"todo": K` and status
`"todo"`; it exits 0 when only todos and passes ran; no death sentence
(77 is a normal exit). `ris spec` reads a `.ri`/`.iyi` file holding a
line `todo "reason"` as a todo test.

### 4.5 Change without a silent pass

When a clause's text changes, its version changes and tags holding the
old version are "to review": a passing test may prove the old promise.
`ris check spec` fails with, e.g.:

    1.3: x_test.ri tag holds 7c3e0a11, clause is now b91a22f0
    next: review the test against `ris spec 1.3`, then `ris spec ack 1.3`

`ris spec ack N.M` (or `ack N`: every clause of chapter N) rewrites
each tag item naming the clause to its current version. A prose-only
file citing it gets a tag line inserted at the top of its leading
block (after `#!`) naming every clause its prose names: the acked ones
versioned, the rest unversioned, so nothing it named is dropped.

### 4.6 SPEC_CHANGELOG.md

An entry starts at a heading `## YYYY-MM-DD ...` and runs to the next.
Each `N.M@hhhhhhhh` token in an entry records that version. The
heading form is `## YYYY-MM-DD · 1.3@b91a22f0, 1.5@0c19aa01`, the
reason in the body. Every clause's current version must be recorded in
some entry: a changed clause needs a written reason, without git. A
long list (a baseline) may go in the body to keep lines <= 80.

### 4.7 Commands

- `ris spec [--json]`: one line per clause:
  `N.M  STATUS  FILES  first words`, then
  `N clauses: A ok, B todo, C to review, D uncovered, E unversioned;
  T tagged files, U untagged`. Status, worst first: `to review` (a
  stale tag), `uncovered` (no file), `unversioned` (a file names it
  without a version), `todo` (only todo files), `ok`. JSON:
  `{"clauses": [{"number", "version", "status", "text", "files":
  [{"file", "version", "todo", "own"}]}], "untagged": [...],
  "counts": {...}}`. Exit 0 unless the spec or a tag does not parse.
- `ris spec N` / `ris spec N.M` [--json]: that chapter or clause: its
  text, version, the changelog entries recording it, the files naming
  it (own/shared, version, todo). For an agent's context.
- `ris spec ack N[.M]`: 4.5; prints each rewritten file.
- `ris spec todo [--json]`: every todo test: clause, file, reason.
  JSON `{"todo": [{"clauses", "file", "reason"}]}`.
- `ris check spec`: a part of `ris check`, after deps, before types,
  run serially with format and deps. Skips "no SPEC.md" without a
  spec and "a PATH was given" with a PATH. Fails on: a spec or tag
  that does not parse; a tag or citation naming no clause; a stale
  tag; a clause whose current version no changelog entry records; a
  clause no file names. A clause named only by todo files passes; the
  todo count is printed. Unversioned and untagged files are reported,
  not failed. Each failure ends with a `next:` line.

The inherited Crystal `ris spec` verb (build and run specs in spec/)
is removed with its `s`/`sp` prefixes: no ris program uses it. The
compiler's own `src/spec` library stays for test/*.cr.

### 4.8 `ris init`

`ris init` writes SPEC.md and SPEC_CHANGELOG.md like AGENTS.md (kept
when present), and NAME_test.ri: one clause `* 1.1 NAME prints a
greeting.`, an entry recording 1.1's version, and a todo test tagged
with it. `ris check` is green on arrival (1.1 is todo). AGENTS.md
gets the tag rule: "Name the clause a test proves: `# spec: N.M`, then
`ris spec ack N.M`."

### 4.9 Example

Clause `* 1.3 The blog starts in an empty directory: the posts
directory is created when it is missing.` is added with a changelog
entry and a todo test. The agent's task is "do 1.3's todo". It runs
`ris spec 1.3`, replaces `todo` with a failing assertion, fixes the
code, and `ris check` is green. When 1.3's text changes, `ris check
spec` fails as in 4.5 until the test is reviewed and acked.

### 4.10 ris's own clauses

Step A adds these to SPEC.md chapter 6, exactly:

```
* 6.7 `ris spec` links the spec's clauses to the tests that prove them.
  The spec is SPEC.md or spec/*.md (both is an error) at the root: the
  nearest directory holding ris.mod or iyi.mod, else the current one. A
  clause is `* N.M text` under `## N. Title`, continued by indented
  lines; its version is the first 8 hex digits of SHA-256 of its text
  with each whitespace run one space. A file under the root's test/
  names clauses in its leading `#` comment block (`# spec: 1.3@a4f20c19`
  or `# spec: none (reason)`); with no tag line, a `# ... SPEC 1.3`
  comment names 1.3 without a version.
* 6.8 `ris check spec` fails on a spec or tag that does not parse, a tag
  naming no clause, a tag whose version is not the clause's current one
  (until `ris spec ack N.M` rewrites it), a version no SPEC_CHANGELOG.md
  entry records, and a clause no test names. Each failure names the
  command that comes next.
* 6.9 `todo "reason"` ends a test with exit code 77: `ris test` reports it
  as todo, neither pass nor fail, and exits 0 when the rest pass. A
  clause named only by todo tests passes `ris check spec`; `ris spec
  todo` lists them. `ris init` writes SPEC.md with one clause,
  SPEC_CHANGELOG.md recording it and a todo test naming it.
```

## 5. Alternatives considered

- Map file (`spec.map`): a third place that goes stale when tests move.
- List of tests inside SPEC.md: every new test edits the spec.
- Clause number in the test file name: one test proves several clauses.
- Labels (`[classes]`) instead of numbers: names that go stale.
- Tool-managed renumbering with hidden ids: noise for no gain.
- Version counter (`1.3v2`): depends on someone bumping it.
- Git commit in the tag or the changelog check: changes on rebase,
  absent in tarballs; the changelog records versions instead.

### Declined review items

- Per-file ack and a `(wording)` marker: the changelog entry already
  forces a written reason per version.
- A results file for a FAIL status: a new state; `ris test` reports
  failures.
- `ris spec todo --write` and generated-todo bookkeeping: the todo
  tests for ris's own clauses are one-time hand work.
- `# spec-todo:` for refused tests: a todo there is an ordinary file.
- Security, scale and malformed-SPEC sections: a parse error is a check
  failure; the scan is cheap until measured otherwise.
- A `RIS-TODO:` sentinel line and a todo age warning.
- Section renames, fenced blocks and a demo clause: cosmetic.

## 6. Risks

- A typo fix forces an ack of every test naming the clause: one
  command, and the changelog entry says it was a typo.
- 62 prose citations show "unversioned": step F acks them.
- A todo test can stay forever: the count is always printed.
- The root rule: ris's own repository has no ris.mod, so the "current
  directory holding a spec" arm is what finds it.

## Implementation plan

Precondition met: the user confirmed the open items (decisions.md,
"Confirmed later", 2026-11-10). Each step ends with
`test/cli/spec_verb.py` (the steps done so far) green, plus the
repository's own test of the step, then review and commit. The
uncovered-clause failure lands with `todo` (D), together with todo
tests for ris's uncovered clauses, so `ris check spec` on ris never
turns red.

Gate: `test/cli/spec_verb.py`, tagged `# spec: 6.7, 6.8, 6.9` (acked),
modelled on test/cli/identity_floor.py and check_verb.py (scratch
projects, the real binary); run by the workflow beside check_verb.py.
Cases, by step:

- A, parsing: SPEC.md and the same spec split in spec/ give the same
  report; both present fails; a clause continued over lines; a heading
  mismatch and a duplicate number fail; a reflow keeps the version;
  the version equals Python's SHA-256 prefix; a tag with and without
  version; prose read only without a tag line; `iyi SPEC 1.2` and
  `SPEC 0.1.0` not read; `none (reason)` accepted, `none` alone and
  junk after `spec:` refused; a file naming two clauses counts for
  both; `ris spec 1.2` prints only 1.2; `--json` keys; the old verb
  is gone (`ris spec --help` is the new usage, `ris s` unknown).
- B, versions: a text change makes "to review"; `ack 1.2` fixes it;
  `ack 1` acks the chapter; ack of a prose file inserts a tag line
  keeping its other citations.
- C, check: `ris check spec` passes a clean project; fails on a stale
  tag, a tag naming no clause, a version no entry records, a parse
  error, each with `next:`; skips without SPEC.md; `ris check` shows
  six part lines with spec after deps; `ris mcp` lists the part.
- D, todo: a todo test exits 77 and `ris test` says todo, exits 0;
  with a failing test it exits 1; JSON counts; `ris spec todo` lists
  it; a clause with no file fails `ris check spec`; a todo-only clause
  passes.
- E, init: `ris init` writes SPEC.md, SPEC_CHANGELOG.md and a todo test;
  `ris check` is green on arrival; existing SPEC.md is kept.

A. Parse, report, old verb out, SPEC clauses.
   Create: src/compiler/iyi/command/spec_clauses.cr,
   test/cli/spec_verb.py.
   Modify: src/compiler/iyi/command.cr (exact `spec` dispatch to
   `spec_command`, help line), SPEC.md (6.7-6.9), SPEC_CHANGELOG.md
   (entry with the three versions), .github/workflows/ris.yml.
   Delete: src/compiler/iyi/command/spec.cr,
   test/compiler-cli/crystal-spec_test.cr,
   test/compiler-cli/fixtures/hello-world_spec.cr.
B. Versions: "to review", `ris spec ack`.
   Modify: spec_clauses.cr, spec_verb.py.
C. `ris check spec`.
   Modify: src/compiler/iyi/command/check_suite.cr (CHECK_PARTS,
   check_skip, check_part, check_next_hint, no paths passed, serial
   set, usage), src/compiler/iyi/command/mcp.cr (part enum,
   description), spec_clauses.cr, test/cli/check_verb.py (six parts),
   SPEC_CHANGELOG.md (baseline entry recording every clause's
   version), spec_verb.py.
D. `todo` and coverage.
   Modify: src/iyi/prelude.iyi (`todo`),
   src/compiler/iyi/command/test.cr (verdict, counts, JSON, summary,
   exit), spec_clauses.cr (`ris spec todo`, uncovered fails),
   spec_verb.py.
   Create: test/spec/N_M_test.ri, one todo test per uncovered clause
   of ris.
E. `ris init`, docs.
   Modify: src/compiler/iyi/command/init.cr, test/cli/init_project.sh,
   test/cli/check_verb.py (init file list), spec_verb.py, AGENTS.md
   (tag rule), CHANGELOG.md.
F. Ack ris's own prose citations: `ris spec ack N` for each chapter.
   Modify: the test files citing SPEC clauses (tag lines only).
   Count before and after with
   `./bin/ris spec | tail -1`.
