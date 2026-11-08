# Structural review (egm-structural)

Target: doc/drafts/fileserver-outgoing.md. Sound; no Blockers. All
lines are 80 chars or fewer. Required sections are present; prior B4,
M3, M5, M8 are fixed structurally.

## Major

* T1 (506-524): Review-items table targets are not headings ("Terms",
  "File close", "the cap") or do not match heading text (103, 199).
  Give Terms an H2; copy heading text exactly.

## Nit

* Review-ID tags in headings are uneven (103, 54 untagged).
* Alternatives and Risks would sit better right after Change.
* LM/AR/CT in the table (190-192) are not defined.
* Phase 2 (350) does not say "gated on its own" like Phase 1.
* "..." in doc-comment blocks (313-332): say it keeps lines.
* Fences have no info string.
* "Behaviour, unchanged" and "Each answer, exactly" overlap.
* Probe labels are not in citation order (P3a before P3).
