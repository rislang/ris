# Implementation readiness (egm-implementation-readiness)

Verdict: not ready.

## Blockers
1. Open questions Q2-Q4 left to implementer; decide them.
2. No file list or phases: fileserver.iyi, new test/ris/fileserver.ri,
   check.sh block, bench file, router comment; ris-website out of scope.
3. Body read wrong: read_str returns after one fill
   (src/iyi/io.iyi:165-181); count Int32 vs Int64 size; reserve does
   to_i32 (src/iyi/tape.iyi:893). Spell out loop; state short-read
   behaviour; decide cap.
4. Header values (tag, stamp, Content-Range) built in serve's scratch;
   Outgoing#header uses value.as_tape (http.iyi:2247,2254): if a view,
   fields dangle after serve returns. Confirm as_tape copies or build
   into caller-owned storage.

## Major
5. Give new helper signatures (not_found(res), range_applies?(Incoming),
   imports, drop Content-Length line).
6. Doc comments go stale (fileserver.iyi:13-14, 36-37, 49-50).
7. bench file runs on iyi, which may lack Incoming/Outgoing: move,
   remove or port.
8. Test plan: file name, how requests are driven, temp dir, PASS line;
   missing cases (If-Modified-Since, If-Range mismatch, suffix range,
   NUL/backslash, redirect with query, missing index, empty file, HEAD
   Content-Length); RIS_TAPE_STATS growth checks.
9. Say explicitly whether HEAD reads the file; length 0 skips opening.

## Nit
10. Header counts per status. 11. Exact body strings. 12. Fold SPEC
section into Change.
