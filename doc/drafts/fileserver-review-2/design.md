# Design review (egm-design)

Target: doc/drafts/fileserver-outgoing.md. Prior B1-B4, M1-M11 are
resolved in text (M1 with the misplaced check below). No Blockers.

## Major

* G1 (158-163): the length check belongs in `format_head`; public
  `Server.format_response` (src/std/http.iyi:2444-2447) is reached
  from test/ris/server_groups.ri:73-76 and samples/ris/serve.ri:69-72
  without `answered_on_tape?`.
* G2 (122-141): block `header` rules are missing: refuse nested
  `res.header` in the block; run `check_line` after the block and cut
  `@text` back on refusal; check the line cap first; make `@spans` at
  full size (2 x LINES, as http.iyi:2230); `@text` can move
  (`owned_resize`, src/iyi/tape.iyi:902-917), spans survive as
  offsets; reuse `append_span`/`String::Span` (tape.iyi:919-924);
  write Content-Type after the read so the 500 keeps none.
* G3 (470-475): answer the P1b question: treat it as a soundness hole.
  The inline value lives in `call`'s scratch, and `res` is read after
  `call` returns (http.iyi:2453-2455). Suspected cause: `tape_text`'s
  "viewing" returns in
  src/compiler/iyi/semantic/tape_shrink_checker.cr:514-548 (not
  traced). The first review said that very inline form was refused,
  so the result depends on context. File a compiler bug, add a
  negative gate, run a use-after-free probe.
* G4 (255-264): RFC 9110 5.6.7 says a recipient MUST accept all three
  HTTP-date forms; 13.1.3 lets a server ignore only invalid dates.
  Parse RFC 850 and asctime too (about 30 lines), or document the
  deviation. Specify invalid-fixdate handling.

## Cap and HEAD

500 over 413 is right; HEAD = GET's 500 matches 9.3.2, but a
resuming downloader cannot learn an over-cap size: list under Risks.
Log the 500. State whether 16 GiB holds under overcommit=2. An unset
length falls back to the body; the bodiless branch (http.iyi:2434)
still drops it on 304: say so.

## Nit

* `reserve` is tape.iyi:895 and takes `Int32 | Int64`; cite
  io.iyi:165, tape.iyi:875, 909-910 for the clamp.
* `read_str` pushes byte by byte (io.iyi:177-180).
* Recheck doc ranges for "copied out by the server" wording.
* Tests: invalid-form fixdate; a 33rd line via the block form.
