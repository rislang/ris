# EGM consolidated review — spec-cli.md

Mode: consolidated, stages 5-9. FeatureRange 1-167, DetailedRange
168-196. Reports: zoom_out_report.md, comprehension_report.md,
critic_report.md, intermediate_zoom_out_report.md,
implementation_readiness_report.md. Stage 8 arbitrated scope; its
smallest-form fixes are the action items. decisions.md predates the
user's later decisions (mandatory coverage, todo tests), which stand.

## 🔴 Blockers

1. **Unit = file.** Tags from the leading comment block; outcome fail >
   todo > pass; `todo` ends the file.
2. **Scanned set:** files under test/ and bench/ of the root (ris.mod or
   ris.mod), `#` comments (.ri .ri .cr .sh .py); src/ and std/
   citations are not tags; prose regex `SPEC \d+\.\d+`. Recount 63/8
   with the command, one unit.
3. **8 hex digits** for the version.
4. **Rewrite the plan to the amended design** (no `--write`, no git,
   no retired/letters, no FAIL status, clauses 6.7-6.9).
5. **Old verb removal:** delete crystal-spec_test.cr and its fixture;
   exact `spec` dispatch to `spec_command`; help line.
6. **`spec` check part:** every touch point in check_suite.cr, mcp.cr,
   command.cr listed (implementation_readiness_report R-B4).
7. **`todo`:** prelude signature and exit 77 (wasm too); test.cr
   verdict, counts, JSON, summary, exit 0 with only todos, no death
   sentence.
8. **File allowlist** per step, Create / Modify / Delete.

## 🟡 Majors

9. Numbering: keep SPEC.md's rule (new clause last; removed number
   unused; tag naming it fails).
10. Changelog heading `## DATE · 1.3@b91a`; every current version in
    some heading; no git.
11. Clause grammar and hash input (Z-M8).
12. Tool's own clauses 6.7-6.9 written in the draft; step A adds them.
13. Step order: no-test failure lands with todo, so `ris check` stays
    green between steps.
14. `ris init`: SPEC.md + SPEC_CHANGELOG.md like AGENTS.md; template
    with one todo-tested clause; AGENTS.md tag rule.
15. `ris spec` statuses (ok, to review, uncovered, unversioned, todo),
    columns, JSON keys; `ris spec ack N[.M]` behaviour (prose → tag).
16. Gate as a grouped list with the missing cases (R-M5), harness after
    bench/identity_floor.py.
17. Precondition: user confirms unconfirmed items; decisions.md updated.
18. Undefined terms: one context sentence (ris, gate, `ris check test`
    vs `ris test`, blog-demo); example message "tag holds 7c3e, clause
    is now b91a"; layout: either read, both is an error.

## 🟢 Nits

19. Renumber 4.3a; AGENTS.md guidance to split large clauses; non-goal
    wording "one new outcome, no new framework"; `ris start` as future
    work; style wording fixes in critic and readiness reports.

## Declined (record in the draft)

- Per-file ack and `(wording)` marker: the changelog heading already
  forces a written reason per version.
- Results file for FAIL status: new state; `ris test` reports failures.
- `--write` and generated-todo bookkeeping: one-time hand work in F.
- `# spec-todo:` for refused tests: a todo there is an ordinary file.
- Security/scale/malformed-SPEC sections: a parse error is a check
  failure; the scan is cheap until measured otherwise.
- `RIS-TODO:` sentinel line; todo age warning.
- Section renames, fenced blocks, demo clause: cosmetic.

## Traceability

| item | st.5 | st.6 | st.7 | st.8 | st.9 |
|---|---|---|---|---|---|
| 1 | — | — | C-B2 | Z-B1 | R-B5 |
| 2 | — | — | C-B1, C-M9 | Z-B2 | R-B6 |
| 3 | nit | nit | C-B3 | Z-M1 | — |
| 4 | M2,M4,M7 | 2,4 | C-M10 | Z-M3..6 | R-B1 |
| 5 | M6 | — | C-M8 | Z-M9 | R-B2,B3 |
| 6 | nit | — | C-M2 | Z-M7 | R-B4 |
| 7 | — | — | C-M2 | Z-M7 | R-B5 |
| 8 | — | — | — | — | R-B7 |
| 9 | M1 | — | C-M3 | Z-M2 | — |
| 10 | M2 | 4 | — | Z-M3 | — |
| 11 | — | — | C-M3 | Z-M8 | R-B6 |
| 12 | M7 | 7 | — | Z-M6 | — |
| 13 | — | — | — | — | R-M1 |
| 14 | — | — | — | — | R-M2 |
| 15 | nit | 1,3 | — | nit | R-M3,M4 |
| 16 | — | — | — | — | R-M5 |
| 17 | M6 | — | C-M8 | Z-M9 | R-M7 |
| 18 | — | 5,6 | nits | nits | — |
