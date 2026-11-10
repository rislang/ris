# Structural review (third review)

Target: doc/drafts/fileserver-outgoing.md

All sections the feature-spec standard needs are present; headings
nest cleanly; review-2 structure nits fixed (Alternatives and Risks
follow Change; line 580 gates Phase 2 on its own). No line over 80.

Verdict: no Blockers, one Major, seven Nits.

## Major

* Lines 6-7, 677-708: intro cites probes P1-P9, Evidence lists only
  P1-P8. Add P9 or say P1-P8.

## Nits

* Line 232: "the Now step" does not exist; phases are Phase 0-2
  (lines 556-597).
* Review tags in headings are mixed: "Prerequisite" (91, answers
  MA3), "Behaviour" (271), "Each answer" (310) carry none. One
  convention throughout.
* Lines 716, 733, 740: table targets do not match headings exactly
  ("Router (Files)" is no heading); the 304-length row points to
  Risks / The cap, but lives in the `res.length` section (253).
* Line 741: "Nits ... throughout" is untraceable; name the places.
* P8 (706-708) is cited nowhere; header rules 1 and 5 (205-217) and
  the nested-header gate (577-578) should cite it.
* Lines 226-227: "region.iyi:523-525" is split across a line break.
* Fenced blocks carry no language tag (consistent; mention only).
