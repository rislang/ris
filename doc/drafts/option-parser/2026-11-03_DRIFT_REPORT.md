# Drift report, 2026-11-03

Targets: doc/drafts/option-parser/option-parser.md against commits
1593f5323 and 00d94bc06; AGENTS.md, LEARN.md, README.md and UPSTREAM.md
for OptionParser. A worksheet: not committed (CONTRIBUTING.md).

## option-parser.md

* RisOptions, "a `protected` accessor, so `ris doc` lists only the
  readers": `ris doc std/option_parser` lists `protected def given`.
  The stage 9 resolution cited `command/doc.cr:325`, which filters only
  the prelude listing; a module's listing is `IyiMod.surface`
  (`src/compiler/iyi/iyimod.cr`, `surface_type`), which skips private
  methods only.
* The removed forms: the four stubs (`on` with a block, twice,
  `invalid_option`, `missing_option`) are listed by `ris doc` as plain
  API, with no doc comment saying they are refused. An agent reading the
  listing sees Crystal's block form offered.
* Phase 1 step 1, fields: OptionParser has a field the plan does not
  list, `@count : Int32`, the next registration's index (a separator
  takes a help line but no index, so `@help.size` cannot serve).
* Phase 1 step 1, messages: the plan says the three parse panics are
  "prefixed `option:`"; the Design section and step 4 give them without
  the prefix, and the code follows those (`unknown flag: --x`).
  The plan's sentence is ambiguous.
* Phase 1 step 3: the test's module is `test/option_parser_check`, not
  `test/option_parser`: a module named `option_parser` makes the name
  `OptionParser` mean the module, and the import is refused.
* Phase 1 step 3, cases: not covered from the bench: a short optional
  value given with a space (`-l [LEVEL]`: `-l3`, `-l` then a flag), a
  pair parsed with its value in both spellings (`-n NAME`,
  `--name=NAME`), and an empty value, `--color=` reading `""` (Design,
  last paragraph of RisFlag and RisOptions).
* Phase 1 step 4: check.sh builds option_parser_panics.ri once and runs
  the binary per case, not `ris run … -- CASE`. Same check, fewer
  builds.
* Phase 1 and 2 gates: check.sh was run on minitest directly (with
  `ulimit -n 65536`), not through `bin/minitest-check check`.
* Phase 2 step 8, LEARN.md: the `Program.args` bullet has the form as
  four statements inline, separated by semicolons, not "one sentence
  and the four-line form".

## AGENTS.md

No drift detected.

## LEARN.md

* See option-parser.md, step 8: the form is inline, not four lines.

## README.md

No drift detected.

## UPSTREAM.md

No drift detected.
