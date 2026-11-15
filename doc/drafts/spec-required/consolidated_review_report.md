# Goldfish Review Report

**Target:** `doc/drafts/spec-required/spec-required.md` (lines 1-67)

Decisions D1-D3 are the user's and were not reopened.

## Reviewer Status

| Reviewer | Status |
| --- | --- |
| `egm-design` | completed |
| `egm-codebase-details` | completed |
| `egm-implementation-readiness` | completed |

Breakdown: 3 Blocker, 8 Major, 3 Nit.

## Answers to the open questions

Q1 (std/ scale). Recommendation: yes, one mark per module, with a
ratchet. Each std module carries one module-level todo or
`@[NoSpec("reason")]` covering its public defs as of now. A public
def added later to that module still fails. `ris check spec` prints
the count, so the backlog can only shrink. One mark per def adds
thousands of lines that say nothing. Decide this before S3.

Q2 (where the proof sits). Recommendation: in the def's own module.
spec-blocks D4 makes the module the test unit. If a call from any
module counts, `ris test post.ri` passes while Post.slugify never
runs. A call from SPEC.md-level blocks under the root (SPEC 6.7)
does not count. Then R2 and R3 name one file: "at the end of
post.ri". This also makes the scan cheaper (Blocker 1).

## Prioritized Findings (Blockers -> Major -> Nits)

### B1. The checker cannot resolve calls - Severity: Blocker
* **Reviewer Lens:** `codebase-details`, `implementation-readiness`
* **Affected Scope:** R2, R3, R5 (lines 28-50)
* **Discrepancy Description**: `spec_blocks_of`
  (spec_clauses.cr:431-458) reads text and keeps only block heads
  and todo reasons; no body, no parse, no types. "Receiver type as
  the checker resolves it" and `Post.slugify` in R3 need a semantic
  pass that `ris check spec` does not have.
* **Rationale & Recommendation**: Choose: a parse plus semantic pass
  (as `ris unsafe` and `build --spec` do), or name matching in text
  (cheap, false matches, no receiver). Write the coverage key
  (class vs instance method: `Post.x` vs `Post#x`). Q2's
  own-module answer narrows the scan.

### B2. "Public" is not one predicate - Severity: Blocker
* **Reviewer Lens:** all three
* **Affected Scope:** R2 (lines 28-30)
* **Discrepancy Description**: "under `std/` internals marked
  `@[Ffi]`" mixes a path rule and a mark. `@[Ffi]` marks a module
  or file in any project (program.cr:1422-1424,
  ffi_boundary_checker.cr:39). `protected`, `lib` funs and
  `@[PointerUnsafe]` defs are not covered.
* **Rationale & Recommendation**: One rule: a def is public unless
  `private`/`protected`, inside a `lib`, or in an `@[Ffi]` module;
  no path condition.

### B3. A call is not a proof - Severity: Blocker
* **Reviewer Lens:** `design`
* **Affected Scope:** R2 (line 31)
* **Discrepancy Description**: `x = Post.slugify("a")` followed by
  an unrelated assertion counts as cover.
* **Rationale & Recommendation**: The call must appear in an
  assertion line, or the block is a `todo` naming the def.

### M1. Def kinds left open - Severity: Major
* **Reviewer Lens:** `implementation-readiness`, `design`
* **Affected Scope:** R2, R5 (lines 28-50)
* **Discrepancy Description**: No rule for `initialize` (called as
  `.new`), operators (`==`, `[]`), abstract defs, implicit calls
  (`to_s`, `inspect`), `def self.x`, inherited defs.
* **Rationale & Recommendation**: State each: `.new` covers
  `initialize`, operator use counts, abstract defs covered through
  any implementation.

### M2. Overloads and macros open holes - Severity: Major
* **Reviewer Lens:** `design`
* **Affected Scope:** R5 (lines 47-50)
* **Discrepancy Description**: One called overload covers the set,
  so a new overload needs no proof: the gap D2 closes. Exempting
  generated defs lets macro-made public API skip D2.
* **Rationale & Recommendation**: Cover per overload, or say it is a
  deliberate hole. Keep `property` exempt; say why other macros are.

### M3. R1's "no spec" and skip rules differ from code - Severity: Major
* **Reviewer Lens:** `codebase-details`, `implementation-readiness`
* **Affected Scope:** Context (line 6), R1 (lines 23-26)
* **Discrepancy Description**: `spec_present?`
  (spec_clauses.cr:145-155) also counts module clauses in
  `src/**/*.ri`. A PATH skips even with `ris.mod`
  (check_suite.cr:93). With no `ris.mod`, `spec_root` falls back to
  the cwd (spec_clauses.cr:131-143): ris's own tree has no manifest,
  so R1 as worded misses the tree S3 turns green. `ris spec` already
  aborts on no SPEC.md (spec_clauses.cr:119-121).
* **Rationale & Recommendation**: Define "no spec" as zero clauses
  of any kind under the root; state that a PATH still skips; say the
  root is `spec_root`'s, not only `ris.mod`.

### M4. The R1 hint points to a command that refuses - Severity: Major
* **Reviewer Lens:** `codebase-details`
* **Affected Scope:** R1 (lines 24-25)
* **Discrepancy Description**: `ris init` aborts when `ris.mod`
  exists (init.cr:93-97), the exact case the error is printed for.
* **Rationale & Recommendation**: Print the SPEC.md and block form
  in the error itself.

### M5. `@[NoSpec]` is underspecified - Severity: Major
* **Reviewer Lens:** `codebase-details`, `implementation-readiness`
* **Affected Scope:** R4 (lines 43-45), S1 (line 54)
* **Discrepancy Description**: Needs an `AnnotationType`
  (program.cr:1424) and a reason check like
  ffi_boundary_checker.cr:75. `ris unsafe` lists four safety marks
  (unsafe.cr:63-68); NoSpec lifts no safety rule, so listing it
  there changes that command's meaning and help. No placement rule
  (def only, or module) and no empty-reason error. S1 puts only
  R1-R3 into SPEC.
* **Rationale & Recommendation**: Give grammar, placement (module
  placement is the Q1 answer), the empty-reason error, and where it
  is listed (`ris unsafe` with a separate heading, or `ris spec`).
  S1 adds R1-R5.

### M6. Rollout breaks downstream at once - Severity: Major
* **Reviewer Lens:** `design`
* **Affected Scope:** S1-S3 (lines 54-58)
* **Discrepancy Description**: D1 and D2 turn on together for every
  project with no transition.
* **Rationale & Recommendation**: Land in the order ris tree green
  (with Q1 marks) then flip to error in one commit; tell rispacks in
  the CHANGELOG entry. No global switch (R4 stands).

### M7. Test plan has no cases - Severity: Major
* **Reviewer Lens:** `implementation-readiness`
* **Affected Scope:** S2 (lines 55-56)
* **Discrepancy Description**: "A fixture project per rule" names no
  cases or expected output.
* **Rationale & Recommendation**: List fixtures with stderr and exit
  code: no ris.mod; ris.mod without SPEC.md; module clauses only;
  uncovered def (R3 text, file:line); private def; todo cover;
  `&.name` cover; overloads; NoSpec with and without reason;
  property; operator, `initialize`, abstract; call outside an
  assertion; cross-module call (per Q2).

### M8. Q2 contradicts R2 as written - Severity: Major
* **Reviewer Lens:** `implementation-readiness`
* **Affected Scope:** R2 (line 31), Q2 (lines 64-66)
* **Discrepancy Description**: R2 says "anywhere in the project";
  Q2 leaves it open, so the scan scope and R3's file are undecided.
* **Rationale & Recommendation**: Close Q2 (see above) and reword R2.

### N1. N.M in the R3 hint - Severity: Nit
* **Reviewer Lens:** `design`, `implementation-readiness`
* **Affected Scope:** R3 (lines 37-41)
* **Rationale & Recommendation**: Suggest the next free module
  clause of that file (`# MODULE.N`), not a bare `N.M`.

### N2. Clause that is a todo marker - Severity: Nit
* **Reviewer Lens:** `design`, `codebase-details`
* **Affected Scope:** R2 (line 31)
* **Rationale & Recommendation**: Say "clause exists" relies on the
  6.8 check, and whether a SPEC.md todo-marker clause covers.

### N3. S3 count and acks unstated - Severity: Nit
* **Reviewer Lens:** `implementation-readiness`
* **Affected Scope:** S3 (lines 57-58)
* **Rationale & Recommendation**: Count blocks, todos and NoSpec
  marks separately; include the `ris spec ack` and CHANGELOG steps
  the new clauses need.
