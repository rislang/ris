# Implementation readiness review (fourth draft)

Verdict: ready once two Majors are fixed. MB1-MB6 resolved.

Checked: check.sh:64, check.sh:1187-1188, seven `parse` defs in
time.iyi (2457, 2463, 3635, 3656, 3671, 3689, 3704).

## Major

1. Lines 114-120, 202-204, 776-780: `_instance` and `_class` gates
   use the `+` chain, but P1 saw only `n.to_s` dangle there, and one
   `self` variant was already refused. A gate green today guards
   nothing. Probe the `+` chain in both def kinds or use the
   `k.put(n.to_s)` form; write out the `Filler` and `fill` bodies.
2. Lines 668-673: `test/ris/outgoing_refusals.sh` lacks its check.sh
   hook, program files and pass rule (panic text and nonzero exit?).
   Give a skeleton as Phase 3 does (742-755).

## Nits

3. Lines 366-369, 650-651: name the seven `<grammar>_answer` defs.
4. Lines 652-657: write out the time_http_date.ri check.sh line.
5. Lines 128-131, 646: Phase 0 defined twice.
6. Lines 264, 305: say the block form sets `@state[2]` to 1 just
   before the yield.
