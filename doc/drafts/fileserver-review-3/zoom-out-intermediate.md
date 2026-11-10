# Intermediate zoom-out review (third review)

Target: doc/drafts/fileserver-outgoing.md

The draft holds together. No Blockers, two Majors, three Nits.

## Major 1: the private date parser (401-432, 453-458, 534-535)

The only new code outside the change's purpose; the draft plans to
delete it (667-668). A7 calls the std/time fix "unrelated", but P6
puts it at time.iyi:2776 (`fail` stores an interpolated
`TimeParseError` in `@error`): the same scratch-escape class. The
repair looks local (keep `what` and `@pos`, build on demand as
`refuse` at :2785 does), but :3635 is a second refusal of unknown
cost. Probe both first: if small, fix std/time as its own phase and
drop the helpers, MONTHS table and pivot (418-421); if not, keep the
parser and give A7 the real reason; note mail.iyi:1052. Do not fall
back to fixdate-only: RFC 9110 5.6.7 requires all three forms.

## Major 2: Prerequisite and negative gate (130-140, 558-559, 664)

The copy into `Outgoing` (138-140) is right, enough, and justified
on its own (P2 refuses the local form); keep it. The gate is the
problem: the draft "adds" a file it cannot commit and never says
where it waits. Phase 0 should file the TODO entry with the `Keep`
program (98-114) pasted in, landing with the fix as
`refused/inline_argument_view.ri`. P1 calls the hole
context-dependent (124-125): line 553 should say whether std/http
stores other parameter views (`Incoming`, Router) the copy misses.

## Ranking of earlier findings

1. Date parser. 2. Prerequisite ownership. 3. The 304's lines vs
"nothing after it runs" (288, 307, 320). 4. P1-P9 vs P1-P8.
5. "Now step" / goose-evals and "times" (232).

## Nits

* 205-207, 577-578: nested-header rule guards an unmade misuse.
* 246-249: "length= raises unless the answer is to HEAD".
* 361-386, 641-656: too much inline detail for a design.
