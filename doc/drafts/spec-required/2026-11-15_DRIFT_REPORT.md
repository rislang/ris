# Drift report: spec-required

Draft: doc/drafts/spec-required/spec-required.md
Built: commit 27eb2a03c (SPEC.md 6.8, spec_clauses.cr, check_suite.cr,
test/cli/spec_required.sh). Read-only check, low effort, no reviewers
spawned.

R1-R5 and the S2 fixture list match the build. The test runs the real
`ris check spec` on every S2 case. Drifts:

## 1. @[Ffi] exempts only a whole file (Major)

- Rule: R2, a def "in an `@[Ffi]` module" is not public.
- Code: spec_scan_file skips the file only when `@[Ffi]` is its first
  code line (spec_clauses.cr:1195). An `@[Ffi]` class later in a file
  that holds other code is still scanned, so its defs fail.
- Fix code: track `@[Ffi]` on the owner stack the way NoSpec is
  tracked, and add a fixture with a second, marked class.

## 2. Unacked module NoSpec has its own error (Nit)

- Rule: R5 names the ack step but no message for a mark not yet acked.
- Code: prints "the module's NoSpec mark is ..." and "run `ris spec ack
  --nospec PATH`" (spec_clauses.cr:1331); the test checks it.
- Fix draft: add the message to R5. It is the safe form an agent needs.

## 3. Module NoSpec is told by placement (Nit)

- Rule: R5, the mark goes "on a module header".
- Code: a NoSpec on the first code line is the module's unless a def
  or another mark follows on the next line; a blank line after it makes
  it the module's (spec_clauses.cr:1198-1205).
- Fix draft: state the blank-line rule in R5 or SPEC 6.8.

## 4. Defs below the first spec block are not scanned (Nit)

- Rule: R2 covers every public def.
- Code: the scan stops at the first spec block (spec_clauses.cr:1212).
- Fix draft: say so; spec blocks end the module (spec-blocks), so a
  def after one is already refused there.

## Not checked

S3 (mark count in the commit body, rispacks note in CHANGELOG) was not
checked against the commit.

## R6 (2026-11-15, lead check)

Built as written: spec_drift_failures in spec_clauses.cr; two
fixtures in test/cli/spec_required.sh. No drift.
