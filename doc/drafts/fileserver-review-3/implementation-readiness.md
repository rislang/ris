# Implementation readiness review (third review)

Target: doc/drafts/fileserver-outgoing.md

Ready once the Majors are fixed; no Blockers. Order is right: file
the bug and park the gate (Phase 0), Outgoing copies (Phase 1),
FileServer (Phase 2), gate committed with the compiler fix. Phase 1
closes the hole for std/http whatever the checker accepts; the
gate's `Keep` program does not touch Outgoing, so it stays a true
compiler test; holding it out keeps every phase green.

## Major

1. Lines 132-136, 558-559: "kept ready" names no place or owner;
   the fix has another owner (88-89, 664). Put the full program
   text and the exact check.sh line in the TODO.md entry (or a named
   patch). The `Keep` listing (97-115) lacks a main body and the
   later scratch write of P1; "ending `puts k.first`" (133) is not
   enough to repeat it.
2. Line 135: "check.sh's `refused` list (check.sh:43-50)" points at
   the `expect()` definition; there is no list. Refusals are
   separate `expect` lines (check.sh:63-69). Say "add an `expect`
   line after check.sh:64". Line 137 "the compiler's TODO": name
   TODO.md and its section (TODO.md:11).
3. Lines 122-124, 130-140, 553-554: P1 found five argument forms in
   three def kinds; the gate covers one (a `+` chain in a top-level
   def). A partial fix turns it green. Gate each form (interpolation,
   bare `n.to_s`, instance method, `self` method) or say the single
   gate is a deliberate minimum.

## Nits

1. Line 113: say the refused local form already prints the needle
   'cannot store data made in this def' (P2, 688-689).
2. Lines 558-559: Phase 0 has no done-condition.
3. Line 664: "then commit its gate" reads as a later commit; say
   same commit as the fix (as line 136 does).
4. Lines 139-140, 551-552: say the Phase 1 copy stays after the fix.
