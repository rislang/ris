# Goldfish Review Report (third review)

**Target:** `doc/drafts/fileserver-outgoing.md` (third draft)

**Verdict: not ready.** No Blockers. Six Majors (MB1-MB6), all
fixable in the draft. Every second-review Major MA1-MA7 is resolved
in substance (all reviewers agree). The Prerequisite plan is sound
and correctly ordered; its gaps are ownership and reach (MB2, MB3).

## Reviewer Status

| Reviewer | Status |
| --- | --- |
| `zoom-out` | completed |
| `comprehension` | completed |
| `design` | completed |
| `structural` | completed |
| `style` | completed |
| `zoom-out` (intermediate) | completed |
| `implementation-readiness` | completed |
| `codebase-details` | completed |

Per-reviewer reports are in this directory.

## Second review: resolved?

| Item | State |
| --- | --- |
| MA1 | resolved: check in `format_head` (255-269), gates 570-576 |
| MA2 | resolved: rules 203-220, Span reuse, move conceded 225-228 |
| MA3 | resolved: P1, TODO, negative gate, copy mitigation |
| MA4 | resolved, by added scope (see MB1) |
| MA5 | resolved: order 288-308, case 18 |
| MA6 | resolved: Terms 10-37, tables (targets: nit) |
| MA7 | resolved: 244-253, empty GET 306 |

## Prerequisite plan

Sound and correctly ordered (design, readiness, intermediate
zoom-out). Copying header values into `Outgoing` closes the hole for
std/http and FileServer whatever the checker accepts, and is
justified on its own (P2 refuses the local form); it should stay
after the fix. The gate's `Keep` program does not touch `Outgoing`,
so Phase 1 cannot turn it green; committing it with the fix keeps
every phase green. Gaps: MB2, MB3, MB4.

## Prioritized Findings

### MB1 Private HTTP-date parser - Severity: Major
* **Reviewer Lens:** `zoom-out`, `zoom-out` (intermediate)
* **Affected Scope:** 401-432, 453-458, 534-535, 667-668
* **Discrepancy Description**: A three-form parser plus helpers is
  built only because std/time fails on ris, and is planned for
  deletion. A7 calls the std/time fix "unrelated", but P6 puts it at
  time.iyi:2776, the same scratch-escape class; :3635 is a second
  refusal. mail.iyi:1052 already duplicates `days_from_civil`.
* **Rationale & Recommendation**: Probe the cost of fixing
  time.iyi:2776 and :3635. If small, fix std/time as its own phase
  and drop the parser; if not, keep it and give A7 the real reason.
  Not fixdate-only: RFC 9110 5.6.7 requires all three forms.

### MB2 Parked negative gate has no home - Severity: Major
* **Reviewer Lens:** `implementation-readiness`, `comprehension`,
  `zoom-out` (intermediate), `design` (nit)
* **Affected Scope:** 97-115, 132-137, 558-559, 664
* **Discrepancy Description**: The draft "adds" a gate it cannot
  commit; Phase 0 keeps it "ready" with no path or owner. The `Keep`
  listing lacks main body and P1's later scratch write. Line 135's
  "`refused` list (check.sh:43-50)" is the `expect()` definition;
  line 137's "compiler's TODO" names no file. Line 664 reads as a
  later commit.
* **Rationale & Recommendation**: Phase 0 files a TODO.md entry with
  the full program and the exact `expect` line (after check.sh:64),
  landing as `refused/inline_argument_view.ri` in the same commit as
  the fix. Add a done-condition for Phase 0.

### MB3 Gate covers one of P1's forms - Severity: Major
* **Reviewer Lens:** `implementation-readiness`, `zoom-out`
  (intermediate)
* **Affected Scope:** 122-125, 130-140, 553-554
* **Discrepancy Description**: P1 found five argument forms in three
  def kinds; the gate tests a `+` chain in a top-level def, so a
  partial fix turns it green. Line 553 does not say whether std/http
  stores other parameter views (`Incoming`, Router) the copy misses.
* **Rationale & Recommendation**: Gate each form or state the single
  gate is a deliberate minimum; grep std for stored parameter views.

### MB4 Log test may read a dangling view - Severity: Major
* **Reviewer Lens:** `design`
* **Affected Scope:** 348-359, 381, 553, 658-660
* **Discrepancy Description**: `Log.warn(..., path: path)` passes a
  path built in serve's scratch; the test reads `RisMemoryBackend`
  entries after serve returns. If entries hold views, this is P1
  again; after the fix the call may be refused. P5 shows only that
  it compiles.
* **Rationale & Recommendation**: Probe backend reads after return
  with scratch written between; state whether `Log` copies.

### MB5 Cap memory figure - Severity: Major
* **Reviewer Lens:** `codebase-details`
* **Affected Scope:** 337-344, 543-544
* **Discrepancy Description**: region.iyi:523-526, 529: each growing
  payload reserves 128 MiB on Linux. If `res.body` is one, 1024
  answers reserve about 128 GiB whatever *max* is; "16 GiB at worst"
  and "pass a smaller *max*" do not hold under strict overcommit.
* **Rationale & Recommendation**: Check how Builder bodies reserve;
  fix or reword the claim.

### MB6 304 lines and terms - Severity: Major
* **Reviewer Lens:** `comprehension`, `style`, `structural`
* **Affected Scope:** 7, 230-232, 288, 296-298, 307-308, 320, 677-708
* **Discrepancy Description**: A 304 is decided at step 4 ("nothing
  after it runs") yet carries Last-Modified, ETag, Accept-Ranges,
  while lines are written "only now" at step 8. Line 7 cites P1-P9;
  Evidence ends at P8. Line 232: "Now step", goose-evals undefined,
  and `RIS_TAPE_STATS` counts, not "times".
* **Rationale & Recommendation**: Say who writes the 304's lines and
  when; fix the probe range; define the terms; say what each run
  measures.

### Nits
* `@size` holds `res.length` against Terms (35-37, 183); packed
  `@state` (177-183, 206): name the idiom or use fields.
* Nested-header rule guards an unmade misuse (205-207, 577-578); P8
  cited nowhere; `@state[2]` not cleared on raise (257-259).
* `length=`: "raises unless HEAD" is one rule (246-249).
* 418: 24 bytes with the comma, 23 without.
* Citations: bodiless branch 2434-2438 (253); src/iyi/io.iyi:165
  (336); fileserver.iyi 53/104/120 are 405/416/404 (330);
  region.iyi:523-525 split over lines (226-227).
* `to_unix` nil and Int64-to-Int32 narrowing into
  `days_from_civil` (time.iyi:1784) unsaid.
* Duplicate `check_line` at http.iyi:2479, 2486.
* Mapping table targets differ from headings (716, 733, 740-741);
  heading review tags mixed (91, 271, 310).
* Undefined: `@[OnTape]` (98, 596), `Field` (223), `as_tape` (172);
  `MAX_CONNECTIONS` vs `max_connections` (338, 544, 603); forward
  case refs (539, 548); log "size" is `count` (547, 351).
* Wording: 68, 219, 225, 228 (Linux only), 414-423 colons, 117-118,
  14-17, 474-476 (P4), 532, 540-542; history at 3-6; inline detail
  361-386, 641-656; name a cost level that reopens copying
  (138-140).
