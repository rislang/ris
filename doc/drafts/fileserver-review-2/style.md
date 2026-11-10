# Style review (egm-style)

Target: doc/drafts/fileserver-outgoing.md. No Blockers.

## Major

* S1 (201, 151-153, 218, 251): "length" means the bytes sent, the
  `Outgoing#length` property and a `read_into` parameter. Rename the
  local (e.g. `count`); keep "length" for `Outgoing#length`.
* S2 (40-52, 150-163, 176-192, 319): "answer" means the Response class,
  the Outgoing, the wire reply and a verb; "tape answer" (162) is not
  defined. Define "answer" in Terms.
* S3 (411): "small enough to review" is a subjective reason for an
  untested path. State the race and how the path is checked.

## Nit

* LM/AR/CT abbreviations in the table (190-192) are not defined.
* Subjective words: "obvious" (132), "right" (144), "easy to get
  wrong" (439).
* "No heap" goal (63) repeats Terms; keep the measurable part.
* "minitest" (7, 484) is not defined.
* Review-ID tags in headings take three forms (199, 244, 266).
* The 16 MiB sentence (205-211) is too long; split it.
* P3's 13 requests (498) vs 17 test cases: say it is a subset.
* "(a literal)" (298) is unclear; "That def" (161) is ambiguous.
* "Decision:" is used in some sections and not others.
