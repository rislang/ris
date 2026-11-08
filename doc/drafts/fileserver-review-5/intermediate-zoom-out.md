# Intermediate zoom-out, fifth round

(Saved by the synthesizer; the reviewer had no write tool. It read
codebase-details.md and the draft's memory section only.)

Verified: to_rfc1123 builds a String via HTTP_DATE.format
(time.iyi:2183); the parser holds `@why` Builder(128)
(time.iyi:2726). Under the draft's rule (504) both are uncounted
128 MiB reservations; "counted per answer, from the code" is false
for serve.

Severity: Major, borderline. The delta (+@text) is right, but the
overcommit=2 sizing advice (523-526) uses the absolute figure and is
wrong for FileServer. Fix in one sentence: scope the table to
std/http or add a transient row.

Big picture: the memory section is too detailed; a paragraph ("adds
one growing value; under overcommit=2 each costs 128 MiB") carries
the decision and avoids count bugs. A 128-byte builder reserving
128 MiB is a runtime issue for TODO, not this draft.

N4 (MAX_BODY clash) may rise if a bare `MAX_BODY` could be read as
std/http's 64 MiB. No Blockers.
