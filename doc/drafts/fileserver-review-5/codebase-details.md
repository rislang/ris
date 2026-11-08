# Codebase details review, fifth draft

(Saved by the synthesizer; the reviewer had no write tool.)

Verdict: no Blockers, 1 Major, 5 Nits.

Review 4: M1 partly resolved (see Major); M2 resolved
(fileserver.iyi:132; region.iyi:489-494, 529); M3 resolved
(TODO.md:222-234 = draft 137-151); M4 resolved (check.sh:1196-1203).

## Major

M1 Memory table (503-525; Risks 691-693) counts only std/http.
   serve adds growing values: `modified.to_rfc1123`
   (fileserver.iyi:103 -> String.build, time.iyi:2183, 2452) on
   every file answer, and `HTTP_DATE.parse` (fileserver.iyi:110)
   with `@why` Builder(128) (time.iyi:2726) on If-Modified-Since.
   Each reserves 128 MiB (region.iyi:365-372, 532-535;
   tape.iyi:630, 1166). Peak 7-8, not 6; 768 GiB is low. Slow path
   (http.iyi:2408-2422) uncounted. Add transient rows or limit
   the claim to std/http's fast path.

## Nits

N1 326 private vs protected (http.iyi:2288).
N2 392 vs 681: "about 50" vs "about 40" lines.
N3 630-632 module doc differs from fileserver.iyi:16-19; old
   line numbers.
N4 `MAX_BODY` clashes with std/http's 64 MiB MAX_BODY
   (http.iyi:2566); write `FileServer::MAX_BODY`.
N5 6-7: some citations are new-tree (time.iyi:2785, 2457/2463,
   3529-3532); label them.
