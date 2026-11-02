# Goldfish Review Report: Stage 5, Initial Zoom Out

**Target:** `doc/drafts/option-parser/option-parser.md` (lines 1-205,
first draft)

## Reviewer Status

| Reviewer | Status |
| --- | --- |
| `zoom_out` | completed |

## Prioritized Findings

### 1. RisOptions cannot map a spelling to an entry - Major
* **Affected Scope:** lines 93-108
* **Discrepancy:** entries are kept "under the index of its
  registration", but lookups take either spelling; mapping a spelling to
  an index needs the parser's maps. A parser reference in `found` adds an
  unstated 3.2 constraint.
* **Recommendation:** keep `found` flat; record the spellings with each
  entry, or state the parser reference and its root rule.

### 2. The yield form's rejection reason hits `found` too - Major
* **Affected Scope:** lines 154-156, 15-16, 104
* **Discrepancy:** `found["-x"]?` repeats the flag name and a misspelled
  key silently answers nil, the flaw that rejected the yield form.
* **Recommendation:** lookups raise for a name never registered.

### 3. A typo stops being an error by default - Major
* **Affected Scope:** lines 99-100, 180-182
* **Discrepancy:** without a handler, unknown and missing flags go to
  `found` instead of panicking; only prose guards it.
* **Recommendation:** keep the panic; record into `found` only when the
  program opts in (no-block `invalid_option` / `missing_option`).

### 4. The command redesign goes beyond the root problem - Major
* **Affected Scope:** lines 83-85, 122-129, 176
* **Discrepancy:** the level number and the `OptionParser -> Nil` block
  type exist only for nested commands, and change iyi; no trial program
  uses commands.
* **Recommendation:** defer commands; a ris program dispatches on
  `rest[0]`.

### 5. The block path rests on an unrun probe - Major
* **Affected Scope:** lines 117-120, 177-179, plan step 1
* **Discrepancy:** stored, nilable procs are called "unproven"; the
  probe exists on disk unreported.
* **Recommendation:** run it before review; if refused, drop the block
  path for ris and the two-read-paths risk with it.

### 6. `@[KeepsBlock]` is a compiler feature for one library - Major
* **Affected Scope:** lines 131-143, 159-161, plan step 4
* **Discrepancy:** a new annotation, its lookup and a `ris unsafe`
  exclusion for one def family; the "later libraries" reason is
  speculative.
* **Recommendation:** generic message text or one hard-coded case;
  an annotation when a second library needs one.

### 7. Storage layout in the Design section - Nit
* **Affected Scope:** lines 80-85
* **Recommendation:** state the rule; leave layout to the plan.

### 8. `each(flag)` is speculative - Nit
* **Affected Scope:** lines 104-105
* **Recommendation:** ship `has?` and `[]?` only.

### 9. A left-out optional value equals an empty one - Nit
* **Affected Scope:** lines 97-98
* **Recommendation:** state it as a known limit.

### 10. A new owner class versus a caller's Array - Nit
* **Affected Scope:** lines 21-25, 65-67
* **Recommendation:** keep RisOptions only if findings 1-2 justify its
  SPEC 2.1 duties.

## Resolution (author)

Probe p7 (a stored `String -> Nil` block called with a view) is refused:
"cannot prove opaque callback retain/escape effects". Probe p8 (a stored
`-> Nil` block capturing a Bool and an Int32) builds and runs. The draft
was revised before Stage 6:

* 5: blocks are dropped for ris; Problem records p7 and p8.
* 1, 2, 10: `found` keeps flat entries with both spellings; it also
  holds the registered names, so a lookup of an unregistered name raises.
  RisOptions stays for that check.
* 3: the panic stays the default; `invalid_option` / `missing_option`
  without a block opt in to recording.
* 4: commands deferred (Non-goals); iyi's block type is unchanged.
* 6: `@[KeepsBlock]` dropped; the refusal is the library's own.
* 7, 8, 9: layout moved to the plan, `each` dropped, the limit stated.
