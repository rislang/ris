# Goldfish Review Report

**Target:** `doc/drafts/pool-t/pool-t.md` (1-198)

## Reviewer Status

| Reviewer | Status |
| --- | --- |
| `egm-design` | completed |
| `egm-codebase-details` | completed |
| `egm-implementation-readiness` | completed |

Verdict: the direction is sound, but the draft is not ready. It has
4 blockers and 9 majors. Revise it before any SPEC.md or code change.

## Prioritized Findings (Blockers -> Major -> Nits)

### B1. A fresh handle is stale on arrival - Severity: Blocker
* **Reviewer Lens:** `egm-design`
* **Affected Scope:** lines 84-89
* **Discrepancy Description**: `@gens` starts at 0, and a zero
  generation is defined as stale. `alloc_handle` returns
  `@gens[i]` unchanged, so the first handle to any slot that was
  never freed is stale.
* **Rationale & Recommendation**: Use parity. An odd generation means
  live, an even one means free, and 0 means never live. `alloc`
  bumps the generation to odd and `free` bumps it to even; a wrap
  skips 0. A handle is valid only when its generation is odd and
  equals `@gens[i]`. Parity also fixes M2. State the wrap point:
  2^31 alloc/free cycles per slot.

### B2. `Pool(File)` refusal is not built today - Severity: Blocker
* **Reviewer Lens:** `egm-codebase-details`, `egm-implementation-readiness`
* **Affected Scope:** line 36, Refusals, Step 4
* **Discrepancy Description**: Today SlicePool does not refuse class
  or IO elements:
  - `tape_checker.cr:168-184` checks only Array and RisTree, and only
    for growing values.
  - `growing_in` (:138) accepts class fields.
  - `:157-166` allows `IyiIO` slots.
  - No test proves 6.5 (there is no `# spec: 6.5` tag).
  - The triage citation (region.ri:200) points at unrelated code.
* **Rationale & Recommendation**: Call this new compiler work in
  `check_fields`, give the exact message, and cover SlicePool and
  Pool together. Add a 6.5 proof. Fix the citation in triage.md.

### B3. "No def" gives no custom refusal message - Severity: Blocker
* **Reviewer Lens:** `egm-implementation-readiness`
* **Affected Scope:** lines 105-108, test 7
* **Discrepancy Description**: When no def exists, the compiler
  reports a generic undefined-method error, so test 7's message match
  fails.
* **Rationale & Recommendation**: Add `push`, `<<` and `realloc` defs
  whose body is `{% raise "..." %}`, the pattern at tape.ri:2371. The
  other option is a name check in `call.cr` (~628/685). Give each
  message's exact text.

### B4. `Handle.new` "outside std" has no mechanism - Severity: Blocker
* **Reviewer Lens:** `egm-implementation-readiness`
* **Affected Scope:** lines 109-110, test 7
* **Discrepancy Description**: No semantic pass checks for std-only
  visibility. Handles can be forged anyway, through `.load` or a
  zeroed struct.
* **Rationale & Recommendation**: Drop this refusal and
  `refused/pool_handle_new.ri`; the generation check at use is the
  real guard.

### M1. The test layout and the proof wiring are wrong - Severity: Major
* **Reviewer Lens:** `egm-codebase-details`, `egm-implementation-readiness`
* **Affected Scope:** lines 126-128, tests 1-10, Step 5
* **Discrepancy Description**: The existing 6.2-6.6 proofs follow one
  pattern:
  - Each is a `test/ris/*.ri` file with a `# spec: 6.N@hash` header,
    run by `test/ris/check.sh`.
  - Compile refusals live in `test/ris/refused/`.
  - No `src/ris/*.ri` file has a `spec N.M` block yet.

  AGENTS.md describes `test/cli/` plus spec blocks, so the two
  sources disagree.
* **Rationale & Recommendation**: Name the exact files and how
  check.sh runs each one (plain run, refused with a fragment, or a
  panic with an exit code). Then pick one:
  - (a) tag the tests like 6.2-6.6;
  - (b) add the first spec block to tape.ri, after confirming that
    `ris check spec` accepts runtime modules.

  Recommendation: (a) now, to match its neighbours.

### M2. Double free by index is silently accepted - Severity: Major
* **Reviewer Lens:** `egm-design`
* **Affected Scope:** lines 121-122
* **Discrepancy Description**: The slot goes onto the freelist twice,
  so two owners share it. 6.3 checks membership before mutation.
* **Rationale & Recommendation**: With parity (B1), `free(i)` on an
  even generation panics with "ris: Pool slot N already free". Add a
  test.

### M3. Negative indices pass the check - Severity: Major
* **Reviewer Lens:** `egm-design`
* **Affected Scope:** lines 90, 111-112
* **Discrepancy Description**: `h.@index < size` accepts a negative
  index, and a handle read with `.load` can carry any Int32.
* **Rationale & Recommendation**: Compare as unsigned, or check
  `0 <= i < size`. Add a negative index to tests 6 and 8.

### M4. The body contradicts the recommendations - Severity: Major
* **Reviewer Lens:** all three
* **Affected Scope:** lines 41-95 vs Q1-Q3
* **Discrepancy Description**: The body uses lazy `@gens` and an
  untyped `Pool::Handle`; the recommendations are always-stored
  generations and `Handle(T)`.
* **Rationale & Recommendation**: After answering Q1-Q6, rewrite the
  API and layout sections so they follow the answers.

### M5. Compiler sites hard-code pool names - Severity: Major
* **Reviewer Lens:** `egm-codebase-details`, `egm-implementation-readiness`
* **Affected Scope:** Steps 3-4
* **Discrepancy Description**: Pool(T) gets no tape treatment until
  "Pool" is added at these sites:
  - `tape_checker.cr:132-135`
  - `tape_owner_checker.cr:43-44`
  - `tape_shrink_checker.cr:2552, 3706-3707`
  - `call.cr:628, 682-685`
  - `tape_escape_checker.cr:38`
* **Rationale & Recommendation**: Add a step that lists each edit.
  For Q1 c, check_tape_copy must also accept a Handle generic.

### M6. `checked`/`default_value` are private - Severity: Major
* **Reviewer Lens:** `egm-codebase-details`
* **Affected Scope:** Step 3
* **Discrepancy Description**: Both are `private def` inside
  SlicePool (tape.ri:3526, 3543), so Pool cannot call them. Pool does
  not need `default_value`.
* **Rationale & Recommendation**: Move `checked` into a shared
  helper. Remove `default_value` from the step. Keep Pool in tape.ri,
  because `RisPoolStorage` is private there (:3944).

### M7. Pool waste is not tracked per field - Severity: Major
* **Reviewer Lens:** `egm-codebase-details`, `egm-implementation-readiness`
* **Affected Scope:** tests 3, 9
* **Discrepancy Description**: `@@pool_waste` is one counter per
  thread (region.ri:93-105). The per-field lines are for growing
  Arrays. Test 3 reads "0 after reuse", which holds only if nothing
  else has freed a slot.
* **Rationale & Recommendation**: Assert the global number. Spell out
  the free/reuse sequence. Make `pool_freed`/`pool_reused` calls with
  `sizeof(T)`.

### M8. The panic mechanism and the wrap hook are unspecified - Severity: Major
* **Reviewer Lens:** `egm-implementation-readiness`
* **Affected Scope:** Refusals (runtime), test 5
* **Discrepancy Description**: The draft gives no panic call, no
  message format and no exit code. The test hook is undefined.
* **Rationale & Recommendation**: Panic through
  `RisRegion.size_error(...)` (tape.ri:3539) and give the exact
  strings and exit code. Make the wrap logic a pure helper,
  `Pool.next_gen(g)`, and test it directly, so no mutation hook is
  needed.

### M9. Copy semantics are a decision, not a side effect - Severity: Major
* **Reviewer Lens:** `egm-design`
* **Affected Scope:** lines 68-69, 92-94
* **Discrepancy Description**: A handle from pool A validates against
  its copy A', even after the two diverge.
* **Rationale & Recommendation**: Say this is a typed replacement on
  purpose. Add a test that frees in A and then uses the handle on A'.

### N1. `Array::Link` is not mentioned - Severity: Nit
* **Reviewer Lens:** `egm-design`
* **Affected Scope:** API, Q1
* **Discrepancy Description**: `Array::Link(T, I)` (tape.ri:2052) is
  already a typed, loadable index.
* **Rationale & Recommendation**: Model `Handle(T)` on Link's layout
  and its none sentinel, or say why Pool's indices stay Int32.

### N2. The refusal list and the tests do not match - Severity: Nit
* **Reviewer Lens:** `egm-design`
* **Affected Scope:** lines 105-108, 142, test 4
* **Discrepancy Description**: `refused/pool_realloc.ri` is missing,
  and no test calls `[]=` through a stale handle.
* **Rationale & Recommendation**: Add both.

### N3. Two citations are wrong - Severity: Nit
* **Reviewer Lens:** `egm-codebase-details`, `egm-design`
* **Affected Scope:** lines 9, 116
* **Discrepancy Description**: The only SlicePool link refusal is
  about relocation (call.cr:628), not other tapes. triage.md:62
  cites tape_core.ri:557 as SlicePool, but SlicePool is at
  tape.ri:3500.
* **Rationale & Recommendation**: Cite the cross-tape escape checker
  for line 116. Fix triage.md when 6.1 is acked.

## Open questions: recommendations

All reviewers agree on every question.

* **Q1: c.** Use `Pool::Handle(T)`, 8 bytes, modelled on
  `Array::Link`. A foreign pool of the same type is documented as a
  typed replacement.
* **Q2: a.** Always store generations, with parity (B1). Revisit only
  if goose-evals shows a cost.
* **Q3: a.** Freeing by index bumps the generation; parity requires
  it anyway.
* **Q4: a.** No `push`/`<<`. Use macro-raise defs that name `alloc`
  (B3).
* **Q5: `Pool(T)`.** The compiler messages already say
  "Pool/SlicePool". Record the Ris* exception for both pools in
  UPSTREAM.md now: a rename after 0.1.0 would break callers and
  ripple through M5.
* **Q6: a.** Ship handles in 0.1.0, after B1, B4 and M2 are fixed.
  6.5 also needs proving for 0.1.0 either way (B2).
