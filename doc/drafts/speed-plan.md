# Draft: speed plan (TODO.md, Speed)

Status: revised after EGM review (2026-11-02), reports in
doc/drafts/speed/. Replaces TODO.md's "## Speed" section; AGENTS.md's
"Speed measurement is off" bullet changes in the same commit.

## Proposal

## Speed

At the end of each Now step, run ris-bench's `goose-evals.sh medium`
on minitest (the goose-evaluations ports jq, json, ninja and yaml
against Goose) and put one line per port in the step's commit body.
x = ris time / Goose time, median of 5 runs; lower is faster. A
timing is a baseline and never fails a gate; nothing is timed per
change. Gates stay structural. No item below changes SPEC.

* A loop or block nested in a def keeps its scope mark even when it
  puts nothing on the tape. TapeScopeChecker
  (src/compiler/iyi/semantic/tape_scope_checker.cr) turns a mark off
  when `allocates?` finds no tape growth, but it reaches only each
  def's top body and the program's top level: Finder does not enter
  a def, so its nested While and Block never reach `off`. Each round
  then loads the tape's region, cursor and side and may call
  `__iyi_scope_release`. perf (ris 0ad4691bb): jq
  `Engine#scan_string` is 25-33% of jq's time, mostly that compare;
  yaml `Document#skip_spaces` spends 15-20% on it. Send nested loops
  and blocks through the same check. If scan_string still keeps its
  mark, find what `allocates?` counts there. Gate: IR specs that a
  byte loop in a def has no mark and a loop in a def that pushes to
  a Builder keeps it; check.sh and RIS_TAPE_STATS unchanged.
* String#hash (src/iyi/tape.iyi:218) is byte-at-a-time FNV-32. perf
  on ninja gen-small: `Hash#find` is 34% of the run, 70% of it
  hashing; ninja is at 1.40x. Hash 8 bytes a step like Goose
  (doc/reference/goose/docs/stdlib.md, Hashing), never read past a
  short String's end (it may end before a guard page), and spread
  the result into the low bits the table masks. Hash iterates in
  insertion order (SPEC 7.2), so programs see no change. iyi has the
  same FNV: list it in UPSTREAM.md. Gate: std hash/Hash specs; equal
  copies and views hash equal; strings differing in one byte at each
  position 0-17 hash differently; keys k0..k999 spread over the low
  bits; a String ending at a page boundary hashes without a fault.
