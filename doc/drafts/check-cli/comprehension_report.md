# Stage 6: Comprehension Test — check-cli.md

Reviewer: egm-comprehension, document alone. FeatureRange 1-197.

**What this proposes**
It merges the `ris` CLI's "is it done" commands into one verb, `ris
check`, with an optional part: format, deps, types, unused or test.
With no part it runs all five, format and deps first and the other
three in parallel, printing one line per part with its time, a total
line, and a `next:` hint for the first failure. A single `--fix`
auto-repairs format, deps and types (serially when fixing), then
reports what is left. `ris ok`, the old types-only `ris check`, `ris
vet`, `ris fmt`, `ris mod tidy`, `ris fix`, `ris tool format` and `ris
tool unreachable` are removed without aliases; for one release a
refusal table rejects each and names its replacement. MCP tools shrink
to `check` and `test`. It lists the files to change and a gate,
`bench/check_verb.py`.

**How the existing system works, per this document**
`ris ok` runs the full suite with `-j`, `--json`, `--affected` and
PATH. `ris check` type-checks only and can print a JSON diagnostic
array (`-f json`) used by LSP and MCP `check`. Separate verbs with
different flag styles do formatting (`fmt [--check]`), dependency sync
(`mod tidy [--check]`), unused-code checks (`vet`) and applying
`suggested_edit`s in rounds (`fix`). Crystal duplicates live under
`ris tool`. MCP exposes `check`, `fix`, `test`, `ok`. The LSP
quickfix applies `suggested_edit` in process.

## Findings

1. **Major — §4 holes 1/2: `--json` contract contradicts itself.**
   Hole 1: `types --json` stays the array; hole 2: `--json` is always
   the object, `-f json` the array. Fix: one rule, stated once.
2. **Major — §1: inherited flag meanings undefined** (`--json`, `-j`,
   `--affected`, PATH). What does `ris check foo.ri` run? A plain old
   `ris check FILE` silently changes from types-only to the full
   suite. Fix: define each flag; state the FILE behaviour; refuse,
   warn, or accept the change explicitly.
3. **Major — §2: the "`ris check` (types)" row cannot be refused**: the
   verb still exists. Fix: name it as the exception and say how it is
   handled.
4. **Major — §6: MCP `affected` vs `file` undefined**, and when
   `diagnostics` is returned. Fix: define both and the rule.
5. **Major — §7: where `ris fmt` lives contradicts the table**
   (format.cr listed, note says not found). Fix: state what format.cr
   is and where fmt dispatches.
6. **Major — parts undefined.** One-line definition of each part
   (unused scope; test scope and output; deps = ris.mod/ris.sum sync)
   under the synopsis.
7. Nit — undefined terms: EGM, AGENTS.md "Agent first", LEARN.md,
   USAGE_ERROR value, `suggested_edit`, dev2, Crystal inheritance,
   init's AGENTS.md, `next:` format.
8. Nit — hole 3: is the 8-round cap existing or new?
9. Nit — run order with/without `--fix` split across §1 and hole 5.
10. Nit — §8: expected output of `ris check ./format`.
11. Nit — Q2 overlaps line 37; mark it pending.
