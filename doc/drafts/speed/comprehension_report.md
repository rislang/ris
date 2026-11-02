# EGM Stage 6: Comprehension report

Target: doc/drafts/speed-plan.md, lines 1..End.

## What this proposes

Measure now, optimize later: at each Now step's end, time jq, yaml and
ninja against Goose on minitest, one commit-body line per port, a
baseline not a gate. Optimization starts once check.sh has 0 FAILED,
the benches build and break/RisScopeMove is fixed; then AGENTS.md's
"speed measurement is off" changes to whole-project timing at step
ends. Queued: (1) rounds/blocks that make nothing get no scope mark,
decided by an allow list; (2) rounds that make something cache the
tape top in a local and release with one store; (3) String#hash goes
from byte-wise FNV-32 to 8 bytes a step. Each has a structural gate.

## How the existing system works, per this document

Each round and block keeps a scope mark; at round end the code reads
the tape top from TLS, compares and may call __iyi_scope_release, even
in a pure byte loop (25-33% of jq, 15-20% of yaml). Goose restores a
watermark only in scopes with a nonfixed local. String#hash is
byte-wise FNV-32, ~70% of Hash#find, which is 34% of ninja. Hash
iterates in insertion order (SPEC 7.2), so programs do not see it.

## Findings

1. Major. "goose-evaluations" is never located: path/URL, build and
   run command, inputs "medium" and "gen-small".
2. Major. Timing procedure undefined: tool, runs, inputs, wall/CPU,
   and an example line (`jq medium: ris 1.23s, Goose 1.10s (1.12x),
   best of 5`).
3. Major. Ratios undefined (ris/Goose? lower better?); what moved jq
   from 0.76-0.81x to 0.98-1.14x; whose "own 8-byte table".
4. Major. Order contradicts AGENTS.md until "Then"; change AGENTS.md
   now or state the exception.
5. Major. "implementation C.2" does not resolve; cite
   doc/reference/goose/docs/implementation.md 6.2.
6. Major. Allow list terms undefined (scope mark, views, stores into
   existing storage, calls known to answer no tape value, SlicePool
   growth); no default stated; no compiler pass named.
7. Nit. Bullet 2: cite implementation.md 6.10; gloss region and side;
   no perf number motivates it.
8. Nit. Hash: source of ~70%; Goose hash location; gloss the
   overlapping tail read; settle the iyi/UPSTREAM question now.
9. Nit. Give check.sh's path (test/ris/check.sh) and current count.
10. Nit. Status header says "proposed" but TODO.md already has it.
11. Nit. "No SPEC change" only on bullet 1; say it once for all.
12. Nit. Pin the Goose version next to the ris hash.
