# `ris spec`: decisions so far (2026-11-10)

Input for the design draft; not a design yet.

## Principle

Spec = intent (source of truth), tests = proof, code = derived. A bug
found by hand is a hole in the spec. SPEC.md holds only promises:
numbered clauses. Reasons go to SPEC_CHANGELOG.md, open questions to a
draft, pending decisions to TODO, measurements to bench/.

## Decided

- Every ris program has SPEC.md and SPEC_CHANGELOG.md; `ris init`
  writes both.
- A test names what it proves: `# spec: 1.3@a4f2`. The part after `@`
  is the clause's version: a hash of its normalised text, computed by
  ris. The old prose form "SPEC 1.3" is read too.
- When a clause's text changes the link does not move: the test is
  "to review" until `ris spec ack 1.3` rewrites its tag.
- Git commits appear only in reports (`ris spec 1.3` history), never in
  tags.
- Clause numbers never change: a new clause takes the next free number
  or a sub-number (1.2a); a removed one stays as
  `* 1.4 (retired DATE, see 1.9)`.
- SPEC_CHANGELOG.md entries: free text under a heading
  `## YYYY-MM-DD · 1.3[, 1.5]`; only date and numbers are required.
- `ris check spec` fails on: a tag naming a missing or retired clause; a
  stale version (text changed, no ack); a changed clause with no
  SPEC_CHANGELOG entry for its number.

## Confirmed later (2026-11-10)

- Coverage is mandatory: a clause with no test fails `ris check spec`;
  unfinished work is a `todo "reason"` test (exit 77), listed by
  `ris spec todo`. This replaces "uncovered clauses are reported, not
  failed" below.
- Old Crystal `ris spec` verb removed, short forms `s`/`sp` included.
- SPEC.md or spec/N-name.md; both present is an error.
- Untagged tests allowed; `# spec: none (reason)` marks implementation
  tests.
- Tests live only under test/ (bench/ moves to test/cli/ and
  test/speed/ first); `ris spec` scans test/.
- EGM: only consolidated_review_report.md is kept next to a draft;
  SPEC_CHANGELOG entries point to it.

## Proposed earlier (see above for what changed)

- Remove the inherited Crystal `ris spec` verb (no ris program uses it;
  the compiler's own `src/spec` library stays for test/*.cr) and take
  the name.
- Spec lives in SPEC.md, or in spec/N-name.md files once it passes
  ~1000 lines; the clause number is the address, so splitting changes
  no tag.
- `ris spec` (coverage), `ris spec N` / `ris spec N.M` (print only that
  part, for agents), `ris spec ack N.M`.
- Untagged tests are allowed; `ris spec` lists them; `# spec: none
  (reason)` marks an implementation test.
- Uncovered clauses are reported, not failed, at first.
- `ris start N.M "..."` (red test with tag) as a later, separate task.
- Principle above into ris AGENTS.md and the global CLAUDE.md.
- Draft goes through EGM before code.
