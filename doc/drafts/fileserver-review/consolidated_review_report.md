# Consolidated review: fileserver-outgoing.md

Target: doc/drafts/fileserver-outgoing.md. Stages run: 5 (zoom out),
6 (comprehension), 7 (design, structural, style), 9 (readiness,
codebase details). Stage 8 (intermediate zoom out) is deferred: the
blockers below change the design, so it reviews the revised draft.

Verdict: not ready. The direction (write into the caller's Outgoing)
held up with every reviewer; the draft's mechanism does not.

## Blockers

B1. Header values cannot be stored as drafted. `tag`, `stamp` and the
    `Content-Range` text are built in `serve`'s scratch; `Outgoing#header`
    stores a view (`String#as_tape` is identity, src/iyi/tape.iyi:213).
    Probe (verified): a def doing `res.header("ETag", "\"" + n.to_s +
    "\"")` is refused: "cannot store data made in this def where it
    outlives the def (SPEC 1.1, 3.6)". So the drafted serve would not
    compile either. Needed: res-owned storage for header text, e.g. an
    Outgoing text builder or `header(name) { |w| ... }` writing the value
    into res. That widens scope to std/http. (design B1, readiness B4)

B2. Body read is wrong: `read_str(count : Int32, into)` returns after
    one buffer fill (src/iyi/io.iyi:165-181); `reserve` truncates with
    `to_i32` (src/iyi/tape.iyi:893). Specify a read loop, a size cap
    (at most Int32::MAX, likely far lower), and the short-read answer
    (file shrank after stat: 500, no partial 206). (readiness B3,
    design M4, zoom-out M2)

B3. Open questions hold decisions an implementer must make (HEAD, cap,
    Router). Decide them in the draft. (readiness B1, structural M4)

B4. No Alternatives section (feature-spec standard): keep Response and
    copy out; streaming file body first; keep old def beside; leave
    serving to the caller; a Server.answer variant taking a file.
    (structural B1, design M2)

## Majors

M1. HEAD reads the whole file only to count it, a regression and a DoS
    lever. Proposed by zoom-out: `res.length = n` override in Outgoing,
    used by format_head; ~5 lines. (zoom-out M1, design M5, readiness M9)
M2. Memory peak = file size x requests in flight up to max_connections:
    decide a default cap and its status (413/500); name the follow-up
    (Outgoing file body via existing sendfile, src/socket.cr:372).
    (zoom-out M2, design M3)
M3. No file list or phases: fileserver.iyi, new test/ris/fileserver.ri,
    check.sh, bench .iyi and .sh, router.iyi comment, http.iyi (B1, M1).
    (readiness B2)
M4. bench/std_fileserver_exercise.sh:199 greps a literal source line of
    fileserver.iyi; the .iyi runs on iyi, which lacks Incoming/Outgoing:
    port, move or remove. (design M6, readiness M7)
M5. Test plan: name, driver (real socket like answer.ri), temp dir,
    PASS line; add If-Modified-Since, If-Range mismatch, suffix range,
    NUL/backslash, redirect with query, missing index, empty file, HEAD
    Content-Length, over-cap file; RIS_TAPE_STATS growth 0.
    (readiness M8, zoom-out N4)
M6. Doc comments become false (fileserver.iyi:13-14, 36-37, 49-50):
    give new wording. (zoom-out N2, readiness M6, design N10)
M7. Give new helper signatures: not_found(res), range_applies?(Incoming),
    imports, drop the Content-Length line. (readiness M5)
M8. Goals / Non-goals and Risks & mitigations sections missing (path
    traversal kept, file change between stat and read, memory).
    (structural M2-M3, design M7)
M9. Undefined terms for a newcomer: tape, scratch, ris vs iyi, gate;
    link SPEC 1.9 and AGENTS.md. (comprehension M1-M5)

M10. The File is never closed: the old Response owned it. State
     open, defer close, seek (File#seek, file.iyi:2150). (codebase M3)
M11. The bench .iyi drives old `Server.serve` with `call(req) :
     Response` (bench .iyi:56-131): porting means moving the harness to
     Server.answer, not "follows the new signature". Also
     test/ris/std_text_plain.ri:41 imports std/fileserver without
     calling serve. (codebase B2, M6)

## Nits

Order Problem before Change; fenced code blocks; behaviour list as
bullets or "unchanged, see module doc"; exact bodies and header counts
per status (2-5, not 4-6); unmeasured "it is fast" and "cost nothing";
dangling clause at L47-48; L10 nested clauses; Router comment should
say Router cannot serve files until ported; symlinks out of root.

## Traceability

| Item | Reports |
|------|---------|
| B1 | critic (design), readiness (readiness, codebase) + probe |
| B2 | readiness, critic, zoom_out |
| B3 | readiness, structural |
| B4 | structural, critic |
| M1 | zoom_out, critic, readiness, comprehension N9 |
| M2 | zoom_out, critic, style |
| M3-M7 | readiness, critic, zoom_out |
| M8 | structural, critic |
| M9 | comprehension |

Per-reviewer notes: zoom_out_report.md, comprehension_report.md,
structural_report.md, style_report.md, readiness_report.md, and the
design critic and codebase-details findings folded in above.
