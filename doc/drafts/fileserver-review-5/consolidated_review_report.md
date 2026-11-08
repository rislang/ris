# Consolidated review, fifth draft

**Target:** `doc/drafts/fileserver-outgoing.md` (whole draft) and
the working tree (fileserver.iyi, http.iyi, time.iyi, router.iyi,
check.sh, answer.ri, TODO.md)

Verdict: **not ready**, narrowly. No Blockers; one Major, a one-
sentence text fix. M2-M4 of review 4 are resolved; M1 (memory) is
resolved for std/http but the count misses serve's own values. Six
lenses rate the draft ready; draft and code agree elsewhere.

Reviewers had no write tool; the synthesizer saved their reports.

## Reviewer Status

| Reviewer | Status |
| --- | --- |
| `zoom-out` | completed |
| `comprehension` | completed |
| `design` | completed |
| `structural` | completed |
| `style` | completed |
| `implementation-readiness` | completed |
| `codebase-details` | completed |
| `intermediate zoom-out` | completed (read memory finding only) |

## Review 4 items

* M1 memory: partly. Table 503-527, Risks 691-693, `@given` in
  `@state[3]` (http.iyi:2234); see M1 below.
* M2 clamp: resolved (fileserver.iyi:46, 132; P14).
* M3 gates: resolved (table 112-118, `n.to_s`, P13,
  TODO.md:222-234).
* M4 outgoing_refusals.sh: resolved (747-776; check.sh:1196-1203).
* Nits: resolved except item-table targets (959-986) and wrapping.

## Blockers

None.

## Majors

### M1 Memory count omits serve's values - Severity: Major
* **Lenses:** codebase-details, design (N1, N6), intermediate
  zoom-out
* **Scope:** lines 503-527, 691-693
* **Description:** "counted per answer, from the code" counts only
  std/http. serve adds `modified.to_rfc1123` (fileserver.iyi:103 ->
  String.build, time.iyi:2183, 2452) on every file answer and the
  HTTP_DATE Parser's `@why` Builder(128) (fileserver.iyi:110,
  time.iyi:2726) on If-Modified-Since: 128 MiB each
  (region.iyi:365-372, 532-535). Peak is 7-8, not 6; the
  overcommit=2 advice (523-526) is low. The slow path
  (http.iyi:2408-2422) is also uncounted.
* **Recommendation:** scope the table to std/http's fast path and
  add serve's transient rows, or shrink the section to one
  paragraph: adds one growing value; under overcommit=2 each costs
  128 MiB. The delta (+`@text`) stands. List the 128 MiB-per-builder
  cost in TODO.md as a runtime issue.

## Nits

* 391 vs 680: std/time fix "about 50" vs "about 40" lines (all).
* 326: `refusal` called private; code is protected
  (http.iyi:2288).
* 630-632: module doc differs from fileserver.iyi:16-19
  ("at most `MAX_BODY`"); old line numbers.
* 800-801 vs 807-809: closing `Connection: close` request told
  twice; fileserver.ri:179 has one.
* Line 6: citations at 5b74fe0ff miss the tree (LINES 2220 -> 2222,
  header 2253-2284); some are new-tree (time.iyi:2785, 2457/2463,
  3529-3532). Say which.
* `MAX_BODY` clashes with std/http's 64 MiB MAX_BODY
  (http.iyi:2566); write `FileServer::MAX_BODY`.
* 754-759: no tests for the 33rd line, a server-owned name, or
  `length=` above Int32::MAX; add or say reviewed.
* Code: http.iyi:2539-2541 comment says Outgoing#header asks
  check_line; it uses Outgoing.refusal now.
* 614-616: ETag and date use the block form (fileserver.iyi:
  184-185).
* 98-99: "files it with its gates"; gates land with the fix
  (134-135, 712-713).
* 681-683: "the same reason", "a third copy" lack antecedents.
* 297: gloss `LINES` (defined 486); 287-291 vs 510 "fourth slot"
  vs "two more slots"; 606-607 explain `byte_range`'s Bool | Nil.
* 848-862: Tests block lacks check.sh:1204's comment.
* 805-808: fileserver.ri leaves its temp dir on failure.
* Item-table targets cut with "..." (959-986).
* Long lines 260, 511, 520, 811, 983-984; short line 121-122.
* 4, 33: "EGM", "tape ports" undefined; 7-8 drop "32-core".
* Optional: cite code instead of `Keep` (155-204), `read_into`
  (548-570), helpers (597-608); 1% rule (345-348); say the draft
  is implemented in the tree (3-5).
