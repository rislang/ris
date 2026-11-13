# Implementation readiness, fifth draft

(Saved by the synthesizer; the reviewer had no write tool.)

Verdict: ready. No Blockers, no Majors.

Review 4 M1-M4 and nits resolved (Memory 503-525, http.ri:
2224-2234; clamp fileserver.ri:46, 132, P14; gate table 112-118,
TODO.md:222-234; outgoing_refusals.sh:1-54, check.sh:1196-1203).
serve order 442-461 matches fileserver.ri:69-152; header rules
match http.ri:2260-2284; format_head http.ri:2476-2510.

Nits:
N1 326 "private" refusal; code protected (http.ri:2288).
N2 391 vs 680: "about 50" vs "about 40" lines.
N3 630-632 module doc differs from fileserver.ri:16-19.
N4 799-801 and 808-809 describe the closing request twice.
N5 (code) http.ri:2539-2541 comment says Outgoing#header asks
   check_line; it now uses Outgoing.refusal.
N6 6-8: say http.ri citations moved in the working tree.
