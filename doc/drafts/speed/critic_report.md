# EGM Stage 7: Critic report (round 1)

Target: doc/drafts/speed-plan.md, lines 1..End.
Reviewers: design (1 Blocker, 6 Major, 4 Nit), structural (0 Blocker,
7 Major, 6 Nit), style (3 Major, 11 Nit); all completed. Deduplicated.

## Blocker

B1. Bullet 1 proposes a second analysis (allow list) beside one that
exists. TapeScopeChecker#run/#off turns a mark off unless
TapeCallGraph#allocates? finds tape growth. Root cause, verified by
the Elephant: Finder#visit(Def) returns false
(tape_scope_checker.cr:230) and run calls off only on each def's top
body, so a While or Block inside a def is never turned off. Probe
(scratchpad t.ri: a byte-skip while in a def, --release) keeps
RisRegion::tape loads and __iyi_scope_release in `skip`. Fix: rewrite
the bullet as "turn off nested While/Block marks in defs through the
existing Effects analysis"; IR gate on such a def.

## Major

M1. Allow list asks the wrong question: "calls answering no tape
value" tests the result, but a Nil call can grow a Builder (@sb.push
in scan_string's second loop). Keep Effects as the only decider; the
listed cases become keep-mark gate specs. (design)
M2. Dependency on break/RisScopeMove is likely void: the fix touches
the flag, not reset/RESULT code. It delays the largest measured win.
Restate or drop. (design)
M3. Fast path bullet: __iyi_scope_reset already returns inline when
tape, cursor and side are unchanged; say what is new. A cached top
goes stale at every allocating call (ris allocates by call; Goose
6.10 syncs around calls). One store skips the side walk and page
return above KEEP_WARM: RSS grows, RIS_TAPE_STATS misses it. No perf
evidence. Make it conditional on a profile after bullet 1. (all three)
M4. Ratios undefined ("x of Goose": time or speed?); the jq move names
no experiment; "its own 8-byte table" is ambiguous; ~70% has no
source. Define x = ris time / Goose time once. (all three)
M5. Timing method missing: runs, median/min, inputs, Goose flags,
idle machine; one example commit line. (design, structural)
M6. Policy vs AGENTS.md: timing starts now, AGENTS.md change waits.
Change AGENTS.md now. Policy also says speed work waits for gates,
hash item says independent: name the exception. (design, structural)
M7. Feature-spec standard: no alternatives or risks per item. One line
each (marks: hoist; hash: cached hash, wyhash/fx; risk: a wrongly
dropped mark leaks scratch, mitigated by RIS_TAPE_STATS 0 and
check.sh). (design, structural)
M8. Hash gates weak: "equal strings hash equal" holds for any
function. Add: strings differing in one byte at each position 0-17
hash differently; low-bit spread over k0..k999; unaligned view equals
copy; how a spec puts a String end at a page boundary. Other FNV sites
(tape.iyi:3094, tape_text.iyi:399, std/json.iyi:2569): in or out?

## Nit

N1. Cite Goose implementation.md 6.2 (not C.2) and 6.10.
N2. iyi has the same FNV (iyi string.iyi:408): list it in UPSTREAM.md.
N3. The mark loads region, cursor and side, not one "tape top".
N4. Define "makes nothing" once: "puts nothing on the tape".
N5. Path test/ris/check.sh; current count 8 FAILED.
N6. "No SPEC change" once for the whole section.
N7. Pin the Goose version beside the ris hash.
N8. Style: reflow L13; "a timing never fails a gate"; split long
allow-list sentences; "where the def grows the tape"; gloss the
overlapping tail read; "Hash iterates in insertion order, so programs
see no change"; plain ranges without "~".
