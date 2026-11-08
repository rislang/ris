# Design review, fifth draft

(Saved by the synthesizer; the reviewer had no write tool.)

Verdict: ready. No Blockers, no Majors. Review 4 M1-M4 and nits
resolved. Draft and code agree (http.iyi:2213-2321, 2476-2522;
fileserver.iyi:66-178; time.iyi:2457-2462, 3290-3316, 3669-3730;
check.sh:851-856, 1197-1217; TODO.md:222; router.iyi:527).

Nits:
N1 503-527, 691-693: `Parser@why` is `String::Builder.new(128)`
   (time.iyi:2726), a seventh 128 MiB reservation during an
   If-Modified-Since parse; mention it.
N2 391 vs 680: "about 50" vs "about 40" lines.
N3 754-759: no tests for the 33rd line, a server-owned name, or
   `length=` above Int32::MAX; add or say reviewed.
N4 6: citations name 5b74fe0ff; header moved to 2253-2284.
N5 805-808: fileserver.ri leaves its temp dir on failure
   (fileserver.ri:208-214).
N6 514-515: slow path's `texts` builder (http.iyi:2409) and Hash
   not counted; say the table counts the fast path.
