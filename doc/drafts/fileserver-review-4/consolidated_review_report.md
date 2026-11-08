# Consolidated review, fourth draft

**Target:** `doc/drafts/fileserver-outgoing.md` (whole draft)

Verdict: **not ready**. No Blockers; four Majors, all text or small
design fixes. MB1-MB6 of review 3 are resolved in substance (std/time
Phase 1, Phase 0 TODO entry, five gates, Log claim at
log.iyi:400-402), but MB5's memory text is still wrong (M1).

## Reviewer Status

| Reviewer | Status |
| --- | --- |
| `zoom-out` | completed |
| `comprehension` | completed |
| `design` | completed |
| `structural` | completed |
| `style` | completed |
| `intermediate zoom-out` | completed |
| `implementation-readiness` | completed |
| `codebase-details` | completed |

## Majors

### M1 Memory figure is wrong - Severity: Major
* **Lenses:** design, codebase-details, intermediate zoom-out
* **Scope:** lines 455-463, 627-629
* **Description:** "about 256 GiB ... today's cost with one builder"
  is false. Every growing payload, Arrays too, reserves 128 MiB
  (region.iyi:367-370, 523-535; tape.iyi:1163-1166). Today an
  Outgoing holds 3, the new one 5 (`@spans`, `@given`, `@text`
  added), plus format_head's builder (http.iyi:2422) and `fields`.
  Memory and Risks also disagree.
* **Recommendation:** count reservations from the code, before and
  after; say which this change adds and the strict-overcommit cost.
  Consider folding `@given` into `@state`. No new fixed builder.

### M2 *max* above 128 MiB fails, not 500 - Severity: Major
* **Lens:** codebase-details (confirmed at region.iyi:487-495)
* **Scope:** lines 450-453, 579-580
* **Description:** the body builder's fixed 128 MiB reservation
  ends in "tape side reservation exhausted"; the `Int32::MAX` clamp
  and "pass a larger *max*" are wrong.
* **Recommendation:** clamp *max* below SIDE_RESERVE, or build the
  body with capacity *want*; add a probe at 200 MiB.

### M3 Inline-view gates may be green today - Severity: Major
* **Lenses:** implementation-readiness, comprehension, zoom-out,
  style, intermediate zoom-out
* **Scope:** lines 106-120, 202-206, 776-780
* **Description:** `_instance`/`_class` gates use the `+` chain, but
  P1 saw only `n.to_s` dangle in those defs. "Five forms" counts two
  ways. The reason for five files is misstated (check.sh:43-52).
* **Recommendation:** use `k.put(n.to_s)` there or probe the `+`
  chain; one table P1 form -> gate; write `Filler`/`fill` bodies.

### M4 outgoing_refusals.sh unspecified - Severity: Major
* **Lenses:** implementation-readiness, intermediate zoom-out
* **Scope:** lines 668-673
* **Recommendation:** give the check.sh hook, program files and pass
  rule, as Phase 3 does (742-755).

## Nits

* Replace, not append to, http.iyi:2214-2216 "the one value that
  grows" (583-586).
* HEAD bodies: say FileServer writes the same body and the server
  drops it (http.iyi:2446, 2458); defines the cap 500's length (443).
* Cite all seven `parse` defs (358, 650-651; count is right) and name
  the `_answer` defs; say what `refuse` returns (time.iyi:2785).
* `@state[2]` set to 1 before the yield (264, 305); clear before a
  raise if rescue is possible (289-304).
* Length check on bodiless statuses (332).
* Linux and macOS, not Linux only (310-313, 455).
* Write out check.sh lines; place Phase 3's block by name (657, 679).
* Phase 0 and MAX_FILE written twice (127-131/646, 234/534).
* P11, P12 not cited (811-816); "header B" (801); "tape twin"
  (299); "heap_trap" (811); "reads right" (373); comma splice
  (617-619); "cases 14-15" should be 15 (623); file.iyi:2141 (519).
* Mapping targets not exact headings (838-859).
* Optional: trim `Keep` and `read_into` listings; the 1% rule.
