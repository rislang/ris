# Stage 7: Critic Review — check-cli.md

Reviewers: egm-design, egm-structural (feature-spec-standard),
egm-style. FeatureRange 1-197. Context: AGENTS.md, CONTRIBUTING.md,
command/ok.cr. Findings already in stage 5/6 are not repeated except
where a reviewer raised them to a new level.

## Blocker

- **C-B1 (design, structural). No "Alternatives considered".** The
  feature-spec standard fails a spec with one path and no rejected
  alternatives; "the user chose it" is not a reason. Add a section
  rejecting, with technical trade-offs: (a) `check` stays types-only,
  full suite under another name (`ok`/`verify`); (b) separate verbs
  with uniform `--check`/`--fix`; (c) keep `ris ok` + `ris ok --fix`;
  (d) keep old verbs as aliases.
- **C-B2 (style; = stage 5 B2). JSON contract contradiction**, lines
  95-100. One rule, stated once.

## Major

- **C-M1 (structural). No Goals and non-goals section.** Collect: no
  SPEC change, no dirty-tree guard, `ris test` kept, unused/test not
  fixable, no new lint rules, no LSP change.
- **C-M2 (design, structural). No Risks section** (failure, scale,
  security). Missing: cost of up to 8 whole-program compiles in
  `types --fix` (needs a per-round line); network access from `deps
  --fix` in offline CI; half-fixed tree when a later fixer fails or is
  killed (state fixes are per part and idempotent); unattended agent
  `--fix` rewriting files and the manifest.
- **C-M3 (structural, design). ok.cr behaviour not carried over:**
  JSON step names change (fmt/tidy/check/vet → format/deps/types/
  unused) though hole 2 calls the contract unchanged; `skip` and
  `stopped` statuses undefined for the new parts; exit code of an
  explicitly named skipped part (`ris check deps` with no manifest);
  `next:` hints name removed verbs; `-j` is test-only. Gate: "five
  part lines, skip allowed", seeded no-manifest and no-tests cases.
- **C-M4 (design). deps under PATH**: ok.cr suppresses tidy with any
  PATH. Resolve the manifest from PATH (code change, list in §7) or
  document deps as current-directory only.
- **C-M5 (design). Old `ris check FILE` silently becomes the full
  suite** (can exit 1 for non-type reasons). One-release stderr notice
  naming `ris check types FILE`, plus a gate case, or accept it in
  Risks.
- **C-M6 (design). Removed verbs' other flags unmapped** (fmt, fix,
  vet, mod tidy beyond `--check`). Enumerate each from the code: kept
  on the part, refused with replacement, or dropped with reason.
- **C-M7 (style). types `--fix` "until clean" vs hole 3's 8-round
  cap.** Say "up to 8 rounds" or "until no edit applies".
- **C-M8 (style). Unmeasured "fast" for format/deps vs Q2's "cheap
  win".** Give a measured time or drop the claim.
- **C-M9 (style). Output flag `-f/--format` collides with part
  `format`** (`ris check format -f json`). Resolved if `-f` is dropped
  (stage 5 B2 fix).

## Nit

- §1/hole 5 run order split (all three reviewers): state both in §1.
- "This is the only ambiguity" overclaims (`test/` dir).
- MCP `file` vs CLI `PATH...`; make it `paths`; say whether `jobs` is
  omitted on purpose.
- Existing projects' generated AGENTS.md still say `ris ok`:
  migration item; weighs on refusal-table lifetime.
- §7 grep misses interpolated usage (`#{name} fmt`): re-read every
  usage string by hand.
- §7 table cells wrap across rows: move `src` details to a list.
- §5 heading: "Removed `ris tool` entries".
- Wording: status meta-commentary (3-5); "run at once" → "in
  parallel" (16); "every part run" → "that ran" (34); quote the exact
  unused/test `--fix` message in both places (30-31, 182); AGENTS.md
  rule cited is about type names, say "following its rule" (46);
  "universal verb" → name cargo/go/deno (110); "dev2" → commit (137);
  "cheap win" → what it saves (197); hole 5 heading "Fix order".
