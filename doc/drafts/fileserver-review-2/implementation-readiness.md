# Implementation readiness (egm-implementation-readiness)

Target: doc/drafts/fileserver-outgoing.md. Close to ready; no
Blockers. Phases build and gate on their own.

## Major

* R1 (176-242): check order in `serve` is unwritten: 304 vs 500 on a
  big file, 416 vs 500, where Content-Range goes relative to
  `read_into`. Give an ordered list; test big.bin + If-None-Match.
* R2 (255-264, 286-288): `fixdate_unix?` is unspecified: byte layout,
  weekday check, case, `GMT`, ranges, second 60, whitespace, and the
  civil-to-unix conversion. Add malformed-fixdate test cases.
* R3 (158-163): `answered_on_tape?` is not the only writer. Public
  `Server.format_response` (src/std/http.iyi:2444-2447) is called by
  samples/ris/serve.ri:72 and test/ris/server_groups.ri:76 and skips
  the check. Name the raise site; say what `head` true does.
* R4 (346-348, 458): the GET-with-wrong-`length=` raise and
  `length = -1` have no gate. Add cases with pinned results.

## Nit

* tape.iyi:214 (`as_tape`), 895 (`reserve`); `reserve` takes
  `Int32 | Int64`, so the clamp reason holds only for `read_str`.
* `seek` is on `IyiIO` (src/std/file.iyi:2141), not `File`.
* Block `header`: LINES count, name refusal before the block,
  rollback of `@text` on a rejected value, the exact view `each_line`
  yields.
* P1b: name the TODO file and entry; tell the implementer not to use
  the inline form.
* HEAD of an over-max file: add the row and a test (500,
  `Content-Length: 24`).
* check.sh block: give the exact comparison with the stats line.
* Test 4: say how the later date is built.
* 416/500 paths: only one Content-Type line.
