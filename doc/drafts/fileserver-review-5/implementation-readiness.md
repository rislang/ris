# Implementation readiness, fifth draft

(Saved by the synthesizer; the reviewer had no write tool.)

Verdict: ready. No Blockers, no Majors.

Review 4 M1-M4 and nits resolved (Memory 503-525, http.iyi:
2224-2234; clamp fileserver.iyi:46, 132, P14; gate table 112-118,
TODO.md:222-234; outgoing_refusals.sh:1-54, check.sh:1196-1203).
serve order 442-461 matches fileserver.iyi:69-152; header rules
match http.iyi:2260-2284; format_head http.iyi:2476-2510.

Nits:
N1 326 "private" refusal; code protected (http.iyi:2288).
N2 391 vs 680: "about 50" vs "about 40" lines.
N3 630-632 module doc differs from fileserver.iyi:16-19.
N4 799-801 and 808-809 describe the closing request twice.
N5 (code) http.iyi:2539-2541 comment says Outgoing#header asks
   check_line; it now uses Outgoing.refusal.
N6 6-8: say http.iyi citations moved in the working tree.
