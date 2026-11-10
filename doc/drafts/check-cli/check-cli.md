# Draft: one `ris check` verb with parts and `--fix`

Status: the user's final design, revised after the EGM review
(consolidated_review_report.md). It states the design, its holes and
the review items declined. No SPEC.md change is made with it.

Goal: one verb answers "is the work done?" and one switch repairs what
a machine can repair. Non-goal: new analysis; every part is an
existing verb's verdict.

## 1. The verb

```
ris check [format|deps|types|unused|test] [--fix|-f] [-j N] [--json]
          [--affected FILE]... [PATH]...
```

`ris check` reads only, unless `--fix` is given.

The parts, one line each:

| part   | checks                                   | old verb             |
|--------|------------------------------------------|----------------------|
| format | the .ri files under PATHs are formatted  | `fmt --check`        |
| deps   | ris.mod and ris.sum match the imports    | `mod tidy --check`   |
| types  | each target type-checks                  | `check FILE`         |
| unused | no method of a target is unreachable     | `vet FILE`           |
| test   | every `*_test.ri` under PATHs passes     | `test`               |

A target is a PATH's .ri file, or for a directory (the cwd when none
is given) the root module named by its manifest, else every non-test
.ri file in it (ok.cr's `ok_targets`).

Scope rules:

* deps runs only with no PATH and a manifest (ris.mod) in the cwd;
  otherwise its line reads `skip`.
* format narrows to the PATHs' .ri files.
* `--affected FILE` (repeatable) narrows types and test to what a
  change reaches; format, deps and unused ignore it.
* `-j N` is passed to test only.
* A named part with nothing to do prints `skip` and exits 0.

Schedule without `--fix`: format, then deps (serial, fast); then
types, unused and test at once. Report as `ris ok` did: one line per
part with its wall time, `skip` and `stopped` statuses, a total line,
and the first failure in fixed order shows its output and a `next:`
line naming the exact command (`next: ris check --fix`, `next: ris
check types --fix`). Exit 0 only when every part run passed.

Schedule with `--fix` (short `-f`): the same, with the fast fixes at
the start. format and deps are checked; one that fails is fixed
(format the files; sync ris.mod and ris.sum) and checked again. The
parallel parts then run exactly as without `--fix`. So `ris check
--fix` on clean code costs what `ris check` costs and writes nothing.
Types edits are applied only when the part is named: `ris check types
--fix` applies the compiler's `suggested_edit` rounds (fix.cr's loop,
capped at 32 edits per file), then checks types. unused and test have
no fixer: `--fix` does nothing extra there. Nothing writes while the
parallel parts run.

`ris check FILE.ri` now runs the whole suite for FILE (it used to type
check only). Accepted; the CHANGELOG says so. The first argument is a
part only when it is one of the five words: a path named like a part
(`test/`, a file `format`) is reached as `./test`.

## 2. Runner

A named part runs in-process and never spawns parts. Bare `ris check`
spawns the public `ris check PART ...` forms, one per part; there is
no hidden entry. It reuses ok.cr's pieces: `ok_sources`, `ok_targets`,
`ok_root_module`, the runner and the line format. Two exceptions: a
named types or unused part with several targets runs `ris check PART
TARGET` per target, since a compile ends its process; and a named
part other than types given `--json` reports through the runner as
one step. `ris check types --json` stays in-process.

## 3. JSON

`--json` is always the steps object `{ok, steps, failed, output, next,
seconds}`; a named part gives one step. Step names: format, deps,
types, unused, test (breaking: they were fmt, tidy, check, vet, test;
CHANGELOG). The types step carries `diagnostics`: the compiler's
errors as data, `suggested_edit` included (the old `check -f json`
array), `[]` when clean.

`-f` now means `--fix`. The old `ris check -f json` goes: `-f json`,
`-f text` and `--format` given to check are refused naming `--json`.
`ris check types --fix --json` is refused (the fix loop prints text):
run `ris check types --fix`, then `--json`.

## 4. Removed verbs

AGENTS.md: a replaced name is removed, not kept beside its
replacement. The old verbs are removed completely, by the user's
decision: each gets the error any unknown command gets. `ris check`
is the only way. The table maps old to new for this draft and the
CHANGELOG only.

| removed                     | replacement               |
|-----------------------------|---------------------------|
| `ris ok`                    | `ris check`               |
| `ris vet`                   | `ris check unused`        |
| `ris fmt`, `ris format`     | `ris check format --fix`  |
| `ris fmt --check`           | `ris check format`        |
| `ris mod tidy`              | `ris check deps --fix`    |
| `ris mod tidy --check`      | `ris check deps`          |
| `ris fix`                   | `ris check types --fix`   |
| `ris tool format`           | `ris check format --fix`  |
| `ris tool unreachable`      | `ris check unused`        |

Other flags of the removed verbs: `fmt -`/`--stdin-filename`, `vet
--tallies` and `-f json`, `fix --json` have no replacement. Old `ris
check` (types only) changes meaning rather than going: hole 1.

`ris test` stays the everyday verb. `ris mod` keeps context, reach,
release and diff. `ris tool` keeps context, expand, hierarchy,
dependencies, implementations, types, flags, macro_code_coverage.

## 5. Why

* One verb for "is it done" and one word per part, instead of six
  verbs with differing flag styles.
* Precedents: Gradle `check`, Biome `check --write`, Ruff `check
  --fix`, Deno `lint --fix`.
* Counter-precedent: `cargo check`, `deno check` and `gleam check`
  type-check only. Help text, init's AGENTS.md and LEARN.md point the
  quick loop at `ris check types` and `ris test --affected FILE`, and
  the total line shows the cost.

Alternatives considered: keep `ris ok` beside the old verbs (six verbs
stay); `--fix` on every part including types (a slow, wide rewrite on
each run); a hidden `--part-exec` entry for the runner (the public form
suffices).

## 6. Holes and answers

1. **Old `ris check FILE` meant types only.** It now runs the suite
   for FILE; `ris check types FILE` is the old meaning. Scripts that
   used `check -f json` get a refusal naming `--json`.
2. **types `--fix` may not end.** fix.cr's cap of 32 edits per file
   stops it; the check after the last edit is the verdict.
3. **`--fix` on a dirty tree.** It rewrites files as `fmt` did; no
   guard. A killed `--fix` is safe to re-run: each fix is idempotent.
4. **Network.** `deps --fix` may fetch, as `mod tidy` did.

## 7. MCP

Tools after: `check` and `test` (with context and doc); `ok` and `fix`
go. `check {part?, fix?, affected?, file?}` runs `ris check [part]
--json [--fix] [--affected F]... [file]` and returns the steps object.

* `file`: the PATH; every part is narrowed to it.
* `affected`: changed files; types and test check only what they
  reach.
* `diagnostics` is in the types step whenever types ran.

## 8. What changes

src: iyi.cr and command.cr dispatch and help, ok.cr (the runner),
check.cr, mcp.cr, init.cr; bench: ok_verb.py becomes check_verb.py,
plus every script calling a removed verb; test/ris; .github's CI step;
LEARN.md; CHANGELOG. `ris fmt` is dispatched in iyi.cr
(`FORMAT_VERBS`). Interpolated usage strings (`#{name} fmt`) are read
by hand, not only grepped. The LSP quickfix builds edits in process
and does not change.

## 9. The gate

bench/check_verb.py runs the real binary on scratch projects: clean
project green with five part lines; no-manifest case; fixed order; a
check error beats a failing test; `--fix` fixes a misformatted file
and an extra ris.sum entry; `-f` equals `--fix`; `--fix` on clean code
writes nothing; `types --fix` applies a suggested edit; each removed
verb fails as an unknown command, with no hint; bare `ris check` is
green; `--json` shape with diagnostics; MCP tool
list; init's AGENTS.md text.

## Review items applied and declined

Applied: blockers 1-3, majors 5-7 and 10-14, nits 15-20. Major 9
(permanent refusal table) is replaced: the user removed the old verbs
with no refusal at all. Items 4 and 8
(`--fix` order, parts without a fixer) are replaced by the user's
`--fix` rule in section 1.

Declined:

- Hidden `--part-exec` entry: public `check PART` suffices.
- Keeping `-f json` for the LSP: the LSP is in-process; `-f` is now
  `--fix` by the user's decision, diagnostics live in the types step.
- `--fix` running all parts with a `failures` list: next run shows the
  rest.
- Path-collision notice, git-dirty hint, stderr notice for old `ris
  check FILE`: noise; documented instead.
- Manifest lookup from PATH: no stated need.
- Per-round timing: AGENTS.md, nothing timed per change.
- Changed-file names in the report: git diff shows them.
