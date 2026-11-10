# Stage 8: Intermediate Zoom Out — check-cli.md

Reviewer: egm-zoom-out, with stage 5-7 reports. Full file.

Verdict: altitude right. Most stage 5-7 demands raise scope (hidden
exec mode, manifest lookup from PATH, git hints, path notices, three
formal sections). Take the essential fixes in their smallest form;
answer the rest with "kept as ok.cr does" or a one-line decline.
Net: about +25 lines, not +150.

## Blocker

- **Z-B1. Runner spawns refused verbs.** No hidden entry: a named part
  runs in-process and never spawns parts; bare `ris check` spawns the
  public `check PART` forms. Gate: bare `ris check` passes with the
  refusal table active.
- **Z-B2. JSON contradiction.** Smallest rule: `--json` is always the
  steps object; `ris check types -f json FILE` keeps today's array; `-f`
  refused on other parts. Delete line 96's sentence. Accept the
  `-f`/`format` name collision in one line (LSP works in process, no
  consumer migration).

## Major

- **Z-M1.** Alternatives: one 4-line paragraph (types-only `check` +
  `verify`; uniform flags on separate verbs; `ok --fix`; aliases), one
  clause each. Non-goals: one sentence. Risks: two sentences in §4
  (`deps --fix` may touch the network; a killed `--fix` leaves done
  parts fixed, every fixer is safe to re-run). No per-round timing.
- **Z-M2.** Fix order types → deps → format serially, then unused ‖
  test; stated once in §1; hole 5 points back.
- **Z-M3.** deps as ok.cr does: only with no PATH and a manifest in
  cwd, else `skip`. format narrows to PATHs, not `--affected`. Drop Q2
  and the "fast" claim.
- **Z-M4.** Hole 2: step names change (breaking, CHANGELOG); `skip`
  and `stopped` kept; a named part with nothing to do prints `skip`,
  exit 0. Gate: a no-manifest project.
- **Z-M5.** `--fix` ignores parts with no fixer; no special message,
  no gate assertion.
- **Z-M6.** Refusal table permanent; delete Q1.
- **Z-M7.** Map each removed verb's other flags from the code.

## Declined (one line each in the draft)

- Run all parts under `--fix` + `failures` list (stage 5 M3).
- Notice when a part name is also a path (5 M4): fix line 42 instead.
- Git-dirty quick-form hint (5 M8).
- Stderr notice for old `ris check FILE` (C-M5): accept in hole 1.
- Naming changed files (count suffices; git diff shows them).
- MCP `paths`/`jobs`: define `file` vs `affected` in one sentence.

## Nit

- §7: fmt dispatch exists (ok.cr:218 calls it); say where.
- Hole 3: "up to fix.cr's existing limit", cite it.
- Name entries by verb, not line numbers.
- Delete hole 6.
- Name ok.cr helpers to reuse in §7.
