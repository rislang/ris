# Stage 5: Initial Zoom Out — check-cli.md

Reviewers: egm-zoom-out, egm-inventive-catalyst. Target: full file
(1-197). Context: AGENTS.md, CONTRIBUTING.md, command/ok.cr.

## Blocker

- **B1 (catalyst). The runner calls the verbs §2 refuses.** ok.cr runs
  each step as a child of the same binary with the old verbs (`fmt
  --check`, `mod tidy --check`, `check FILE`, `vet FILE`). Under the
  refusal table each exits USAGE_ERROR; renaming them to `check PART`
  recurses into the orchestrator. Fix: split part runner from
  orchestrator; children use a hidden entry (e.g. `ris check
  --part-exec types FILE`) that runs one part in-process. Gate: full
  `ris check` passes with the refusal table active.
- **B2 (both). Two JSON contracts for `ris check types`** (§4 holes 1
  and 2, §6). Line 96 keeps the old array under `--json`; lines 97-100
  make `--json` the object and keep `-f json` for the array. Fix: one
  machine output: `--json` is always the object, types adds a
  `diagnostics` array (as MCP §6 does); drop `-f`, refuse it with "use
  --json"; move LSP/MCP consumers to `.diagnostics`.

## Major

- **M1 (catalyst). `--fix` order leaves types' edits unformatted.** Run
  fixes types → deps → format (format last), or re-run format when
  types changed anything.
- **M2 (both). `--fix` schedule stated twice and differently** (§1 vs
  hole 5). State both schedules in §1; hole 5 points back.
- **M3 (catalyst). Stop-at-first-failure vs `--fix` "reports what is
  left".** Without `--fix` stop early; with `--fix` run every part and
  report all (`failures` list in JSON).
- **M4 (catalyst). "Only ambiguity" is wrong: `test/` is a common
  directory** (ris has one). When a part name is also an existing path,
  print "read as part; use ./test for the directory"; gate
  `ris check ./test`.
- **M5 (both). deps/format scope under PATH and `--affected` is
  inconsistent** (§1 vs §9 Q2 vs ok.cr, which skips tidy with PATHs).
  Decide now: format narrows to `--affected` files; deps runs when a
  manifest is found at or above the PATH, else `skip`. Drop Q2.
- **M6 (zoom-out). `--fix` on unused/test is speculative surface.**
  Either plain check with no special message, or refuse with "unused
  has no automatic fix; use `ris check unused`".
- **M7 (both). Refusal-table lifetime open in §9 Q1 while §2 decides
  it.** Decide in §2; catalyst leans to keeping it permanently (cheap,
  serves stale agent prompts).
- **M8 (catalyst). Counter-precedent cost** (agents used to cargo-style
  `check` pay the full suite). With a dirty git tree and no
  `--affected`, print a one-line hint naming the quick form.

## Nit

- `ris fmt` dispatch not located (§7): find it (ok.cr:218 calls it).
- Line-number citations go stale: name entries by verb or date them.
- Hole 6 repeats §2: merge.
- Fix-loop limit "8 rounds": cite fix.cr's real limit.
- `--fix` report should name changed files, not only a count.
- Unused/test under `--fix`: say "cannot fix automatically: N left".
- Name ok.cr pieces to reuse (`ok_steps`, `ok_sources`, `ok_targets`)
  so no second walker is written.
