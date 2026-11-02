# EGM Stage 8: Intermediate Zoom Out report

Target: doc/drafts/speed-plan.md (unrevised). Verdict: revise, then
pass. Applying every finding would double the section into a feature
spec; the root fix is one defect in an existing pass, one hash
function and one timing rule. The revision should be the same length
or shorter.

## Blocker

B1. Bullet 1: rewrite as the TapeScopeChecker fix (file path, no
line): loops and blocks nested in a def never reach off; send them
through the existing allocates? check. Top-level loops already take
that path. Gates: a byte loop in a def has no mark; a loop pushing to
a Builder keeps it. "If scan_string still marks after this, find what
allocates? counts there." Drop the allow list, the Goose cite, the
RisScopeMove dependency.

## Major

M1. Delete bullet 2 (fast path); a later profile writes its own item.
M2. Drop the start condition: nothing is left behind it. Change
AGENTS.md's "Speed measurement is off" in the same commit.
M3. Reject critic M7 (alternatives and risks per item): TODO, not a
design; check.sh and RIS_TAPE_STATS cover the one real risk.
M4. Trim timing method to two clauses: where goose-evaluations lives;
x = ris time / Goose time, median of N runs. Reject the rest.
M5. Hash: three constraints (8 bytes a step like Goose stdlib.md
Hashing; never read past a short String's end; spread into low bits).
Gates: one-byte difference at each position 0-17 hashes differently;
low bits spread; equal copies and views hash equal. Other FNV sites
are out of scope (two are rolling search hashes; json's is its own
item).

## Nit

N1. "iyi has the same FNV: list it in UPSTREAM.md."
N2. Reject the FAILED count, status header and region/side glosses.
N3. One evidence line per item; pin the ris and Goose versions.
N4. Say "puts nothing on the tape".
