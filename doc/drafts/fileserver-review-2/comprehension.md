# Comprehension review (egm-comprehension)

Target: doc/drafts/fileserver-outgoing.md. Every section could be
paraphrased; no Blockers.

## Major

* C1 (3-5, headings, 506-524): review codes (B1, M7...) are not
  stated; a reader needs the old report. Add a one-line summary per
  item to the table.
* C2 (29, 40, 50, 80, 358): `Incoming`, `Outgoing`, `Server.answer`,
  `Request`, `Response`, old `Server.serve` are not in Terms.
* C3 (63, 139-140, 414-416): "growth moves", "side regions",
  `RIS_TAPE_STATS`, "reserves its own address space" are undefined,
  yet carry the span-validity claim.
* C4 (106-107, 133-137, 304): "view" and the rule that `each_line`
  may build a view when it yields (137) are asserted, not cited.
* C5 (151-161, 251, 458): `length=` contract is ambiguous. The raise
  is on size mismatch but its message and 458 say any GET; 251 sets it
  for empty-file GETs. State the exact condition per method.
* C6 (140, 498-504): P3 is cited for the `@text` design but is the
  full serve run; P3 drove 13 requests vs 17 cases; "minitest" is not
  defined.

## Nit

* "quoted below" (21) but nothing is quoted; "flat Array" (42),
  `@[OnTape]`, UPSTREAM (371), `IYI_PATH` (486) undefined.
* Why some helpers are `protected` (286-290).
* "as Go's are" (174) assumes Go knowledge.
* 304 dropping Content-Type (186, 194) is a change under "Behaviour,
  unchanged".
* Clamp order vs cap (203-205): is a > 2 GiB answer a 500?
* Start -1 lines (136): say they read `@lines` as today.
* Non-goal at 72: add a forward pointer to 257.
