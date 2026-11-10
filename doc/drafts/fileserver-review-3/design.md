# Design review (third review)

Target: doc/drafts/fileserver-outgoing.md

Close to ready: no Blockers, one Major, three Nits.

## Review-2 Majors

* MA1 resolved: check in `format_head` (255-269); gates 570-576, P7.
* MA2 resolved: ordered rules (203-220), Span reuse, "never moves"
  corrected (225-228), every value copied (A6 dropped, 530-532).
* MA3 resolved for this change: P1 run (683-687), TODO, negative
  gate; the draft removes the dangle from its own path by copying.
* MA4 resolved: three date forms (414-432), cases 4-5, RFC 850
  pivot deviation stated.
* MA5 resolved (288-308; case 18). MA6 resolved (10-37, tables).
* MA7 resolved (244-253; empty GET at 306).

## Prerequisite plan

Sound and correctly ordered: the copy does not depend on the fix;
committing the failing gate with the fix keeps the tree green;
filing before Phase 1 is right. But copying only protects Outgoing.

## Major: the log test may hit P1 (348-359, 381, 553, 658-660)

serve calls `Log.warn(..., path: path, ...)` with a decoded path in
serve's scratch; the test reads the `RisMemoryBackend` entries
after serve returns. If entries keep views, this is the same dangle
and the check reads freed bytes; after the compiler fix the call may
be refused and break Phase 2. P5 shows only that it compiles. Probe
backend reads after return with scratch written between; state
whether `Log` copies; widen the Risks bullet (553) into a short std
audit of stored parameter views (`as_tape` stores).

## Nits

* 132-136, 558-559: where the parked gate lives is unsaid.
* 418: "24 bytes after the comma": 24 with the comma, 23 without.
  Fixdate (414-415) and asctime (422-423) offsets check out.
* 205-207, 257-259: `@state[2]` not cleared on raise; say the answer
  is unusable after a raise, since `format_response` is public.
