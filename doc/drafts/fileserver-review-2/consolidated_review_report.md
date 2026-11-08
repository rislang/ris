# Goldfish Review Report (second review)

**Target:** `doc/drafts/fileserver-outgoing.md` (lines 1-525)

**Verdict: not ready.** No Blockers. Seven Majors, one of them a
verified false code claim. All first-review Blockers and Majors
(B1-B4, M1-M11) are resolved in substance. M1 is resolved except
for where the check sits (MA1).

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

The per-reviewer reports are in this directory.

## First review: resolved?

| Item | State |
| --- | --- |
| B1 | resolved by the block form; rules missing (MA2) |
| B2 | resolved; the read loop matches io.iyi:165-181 |
| B3, B4 | resolved |
| M1 | the HEAD design is resolved; the check is misplaced (MA1) |
| M2 | resolved; the sendfile citation is corrected |
| M3-M11 | resolved; M10 verified at src/iyi/file.iyi:28, 32-38 |

## Prioritized Findings

### MA1 The length check misses a writer - Severity: Major
* **Reviewer Lens:** design, readiness, codebase, zoom-out
* **Affected Scope:** lines 157-163, 458-459
* **Discrepancy Description**: The draft says "`Outgoing.new`
  appears only at 2452", and that is false. A public
  `Server.format_response` (src/std/http.iyi:2444-2447) also
  writes an Outgoing. Its callers are test/ris/server_groups.ri:73-76
  and samples/ris/serve.ri:69-72, and they reach `format_head` without
  going through `answered_on_tape?`.
* **Rationale & Recommendation**: Put the length-versus-body check in
  `format_head`, which every path goes through. Correct the claim.
  Add a gate for a GET that sets a wrong `length=`, and one for
  `length = -1` (readiness R4).

### MA2 The block-form `header` is underspecified - Severity: Major
* **Reviewer Lens:** design, zoom-out, readiness, codebase
* **Affected Scope:** lines 122-145, 444-446
* **Discrepancy Description**: These rules are not stated:
  - what happens when the block itself calls `res.header`;
  - that `check_line` runs after the block, and `@text` is cut back
    when it refuses;
  - that the line cap is checked first;
  - that `@spans` is made at full size, not pushed.

  The draft says `@text` "never moves", which is false:
  `owned_resize` can move it (src/iyi/tape.iyi:902-917). Spans
  survive anyway, because they are offsets. The draft also
  overlooks the existing `append_span` and `String::Span`
  (tape.iyi:919-924).
* **Rationale & Recommendation**: State the rules and reuse
  `String::Span`. Consider uniform spans, with every value copied
  into `@text`: `each_line` has one caller (http.iyi:2428) and an
  answer has at most 32 lines. A6 is refused on a cost claim that
  was never measured.

### MA3 The P1b inline-argument question is left open - Severity: Major
* **Reviewer Lens:** design, intermediate zoom-out, readiness
* **Affected Scope:** lines 143-145, 470-475, 491-492
* **Discrepancy Description**: An inline value is made in `call`'s
  scratch, yet `res` is read after `call` returns
  (http.iyi:2453-2455). Accepting the inline form while refusing
  the same value in a local is inconsistent. The first review
  reported that this very inline form was refused, so the result
  depends on context. Suspected cause: the "viewing" returns in
  src/compiler/iyi/semantic/tape_shrink_checker.cr:514-548. This
  has not been traced.
* **Rationale & Recommendation**: Treat it as a soundness hole, not
  a TODO, and answer it before Phase 1. Run a use-after-free probe
  and file a compiler bug with a negative gate. Drop the advice at
  lines 143-145 to keep computed values on the two-argument form.
  If the probe shows a dangling view, this becomes a Blocker.

### MA4 IMF-only If-Modified-Since breaks RFC 9110 - Severity: Major
* **Reviewer Lens:** design, readiness, codebase
* **Affected Scope:** lines 255-264, 286-288, 393-394
* **Discrepancy Description**: RFC 9110 §5.6.7 says a recipient MUST
  accept all three HTTP-date forms, and §13.1.3 lets a server ignore
  only an invalid date. The draft also leaves `fixdate_unix?`
  unspecified:
  - the byte layout and the literal `GMT`;
  - whether the weekday is checked, and whether matching is
    case-sensitive;
  - range checks, and how an invalid fixdate is handled;
  - the civil-date-to-unix conversion. `Time.days_from_civil`
    (src/std/time.iyi:1784) could be reused for it.
* **Rationale & Recommendation**: Parse RFC 850 and asctime as well
  (about 30 lines), or document the deviation from §5.6.7. Specify
  the parse, and add tests for an invalid or malformed date.

### MA5 The check order in `serve` is not written - Severity: Major
* **Reviewer Lens:** readiness, design
* **Affected Scope:** lines 176-242
* **Discrepancy Description**: The draft does not say which answer
  wins when two apply: 304 or 500 for a large file, 416 or 500.
  It also does not say where Content-Range and Content-Type are
  written relative to `read_into`. Without that, the "file
  changed" 500 can carry the file's type.
* **Rationale & Recommendation**: Give the order as a list. Add a
  test for big.bin with a matching If-None-Match. Add a test and a
  table row for HEAD of an over-max file.

### MA6 The draft leans on terms it does not define - Severity: Major
* **Reviewer Lens:** comprehension, style, structural
* **Affected Scope:** lines 3-22, 63, 139, 201, 251, 506-524
* **Discrepancy Description**: Several terms are used but not
  defined:
  - the review codes (B1, M7 and so on) carry no one-line summary;
  - `Incoming`, `Outgoing`, `Server.answer`, `Request` and
    `Response`;
  - "growth moves", "side regions" and "view";
  - "length", which means three different things;
  - "answer" and "tape answer".

  The table targets do not match the heading text.
* **Rationale & Recommendation**: Add these to Terms, rename the
  local `length`, and summarise each item in the table.

### MA7 The `length=` contract is ambiguous - Severity: Major
* **Reviewer Lens:** comprehension
* **Affected Scope:** lines 151-161, 251, 458
* **Discrepancy Description**: The raise fires on a size mismatch,
  but its message and line 458 say it fires on any GET. Line 251
  also sets `length=` for an empty-file GET.
* **Rationale & Recommendation**: State the exact condition for
  each method.

## On the questions asked

* **16 MiB cap and 500**: sound. 500 is right over 413, and the
  cap is on bytes sent. Add to Risks that a HEAD over the cap hides
  the size from a resuming client. Log the 500. Say whether the
  16 GiB worst case holds with overcommit=2.
* **HEAD via `res.length`**: the design is sound. The check must
  move (MA1). Say that a 304 drops the length through the bodiless
  branch (http.iyi:2434).

## Nits (grouped)

* Off-by-one citations:
  - `as_tape` is at tape.iyi:214;
  - `reserve` is at tape.iyi:895, and it takes `Int32 | Int64`;
  - the Outgoing doc is at http.iyi:2213-2217;
  - `LINES` is at http.iyi:2220;
  - Content-Length is written at http.iyi:2434-2438.
* `seek` belongs to `IyiIO` (src/std/file.iyi:2141), not `File`.
* http.iyi:2582-2584 is a doc comment, not code.
* test/ris/fileserver.ri needs `import std/dir` (dir.iyi:464).
* For the check.sh block, give the exact comparison against the
  stats line. For test 4, say how the later date is built.
* Wording:
  - spell out LM/AR/CT in the table;
  - drop the subjective words (132, 144, 411, 439);
  - define "minitest";
  - tag the headings one way throughout;
  - note that P3 ran a subset of the cases;
  - list the 304 that drops Content-Type as a change.
* Structure:
  - move Alternatives and Risks to right after Change;
  - say in Phase 2 that it is gated on its own.
* Add a follow-up to delete the private date helper once std/time's
  parser compiles. Check whether `Time.parse_rfc1123`
  (time.iyi:2266) compiles.
