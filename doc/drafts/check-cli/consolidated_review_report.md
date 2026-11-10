# EGM consolidated review — check-cli.md

Mode: consolidated, stages 5-8 (no implementation plan section, so
stage 9 skipped). Reports: zoom_out_report.md, comprehension_report.md,
critic_report.md, intermediate_zoom_out_report.md. Stage 8 arbitrated
scope; its smallest-form fixes are the action items.

## 🔴 Blockers

1. **Runner must not spawn refused verbs.** Named part runs
   in-process; bare `ris check` spawns `check PART`. Gate: bare
   `ris check` green with refusal table active.
2. **One JSON rule.** `--json` = steps object always; `ris check types
   -f json FILE` = today's array; `-f` refused elsewhere. Delete line
   96's sentence; note the `-f`/`format` collision as accepted.
3. **Alternatives considered** (feature-spec standard): one short
   paragraph, one clause per rejected option.

## 🟡 Majors

4. `--fix` order: types → deps → format, then unused ‖ test; both
   schedules stated once in §1.
5. Carry over ok.cr contract: new step names (breaking, CHANGELOG),
   `skip`/`stopped` kept, named part with nothing to do = `skip`, exit
   0; rewritten `next:` hints; `-j` is test-only.
6. Scope: deps only with no PATH and a manifest in cwd, else `skip`;
   format narrows to PATHs; drop Q2 and the "fast" claim.
7. Define each part in one line (format, deps = ris.mod/ris.sum sync,
   types, unused scope, test scope) and each inherited flag; state
   what `ris check FILE.ri` runs; accept the old `ris check FILE`
   meaning change in hole 1, and name the `ris check` (types) row as
   the one removed spelling that cannot be refused.
8. `--fix` ignores parts with no fixer; no special message.
9. Refusal table permanent; delete Q1 (generated AGENTS.md files keep
   saying `ris ok`).
10. Map each removed verb's other flags from the code.
11. Goals/non-goals in one sentence; two risk sentences (network on
    `deps --fix`; killed `--fix` is safe to re-run).
12. MCP: define `file` vs `affected` and when `diagnostics` returns.
13. Types `--fix` limit: cite fix.cr's real round limit.
14. Line 42: any path named like a part (`test/`) needs `./test`.

## 🟢 Nits

15. Locate `ris fmt` dispatch (ok.cr:218 calls it); fix §7 note.
16. Name entries by verb, not line numbers; name the commit not dev2.
17. Delete hole 6; §5 heading "Removed `ris tool` entries"; §7 table
    rows not wrapped.
18. Name ok.cr helpers to reuse (`ok_sources`, `ok_targets`,
    `ok_root_module`).
19. §7 grep misses interpolated usage strings: re-read by hand.
20. Wording: lines 3-5, 16, 34, 46, 110, 197, hole 5 heading.

## Declined (with reason, record in draft)

- Hidden `--part-exec` entry: public `check PART` suffices.
- Dropping `-f` + `.diagnostics` migration: LSP is in-process.
- `--fix` running all parts + `failures` list: next run shows the rest.
- Path-collision notice, git-dirty hint, stderr notice for old
  `ris check FILE`: noise; documented instead.
- Manifest lookup from PATH: no stated need.
- Per-round timing: AGENTS.md, nothing timed per change.
- Changed-file names in report: git diff shows them.

## Traceability

| item | stage 5 | stage 6 | stage 7 | stage 8 |
|---|---|---|---|---|
| 1 | B1 | — | — | Z-B1 |
| 2 | B2 | F1 | C-B2, C-M9 | Z-B2 |
| 3 | — | — | C-B1 | Z-M1 |
| 4 | M1, M2 | F9 | nit | Z-M2 |
| 5 | — | — | C-M3 | Z-M4 |
| 6 | M5 | F11 | C-M4, C-M8 | Z-M3 |
| 7 | — | F2, F3, F6 | C-M5 | declined notice |
| 8 | M6 | — | nit | Z-M5 |
| 9 | M7 | — | nit | Z-M6 |
| 10 | — | — | C-M6 | Z-M7 |
| 11 | — | — | C-M1, C-M2 | Z-M1 |
| 12 | — | F4 | nit | declined fields |
| 13 | nit | F8 | C-M7 | nit |
| 14 | M4 | — | nit | declined notice |
| 15 | nit | F5 | nit | nit |
