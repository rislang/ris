# Zoom out (egm-zoom-out)

Target: doc/drafts/fileserver-outgoing.md. Scope is tight; prior
B1-B4 and M1-M11 have real answers.

## Major

* Z1 (132-145, 444-446): dual-mode header storage (view lines with
  span -1, block lines as spans) is not the simplest form.
  `each_line` has one caller (src/std/http.iyi:2428); an answer has
  at most 32 lines (http.iyi:2220). Copying every value into `@text`
  costs a few dozen bytes and removes the sentinel. A6's refusal
  rests on an unmeasured cost claim. Adopt uniform spans or measure.
* Z2 (161-163): "`Outgoing.new` appears only at 2452" is false:
  test/ris/server_groups.ri:73 builds one and calls
  `Server.format_response` (line 76; http.iyi:2444-2447), which goes
  through `format_head` but not `answered_on_tape?`. Put the length
  check in `format_head`, or correct the claim.

## Nit

* `@size` storage detail (147-156) is below design level.
* `read_into` body (216-237) could be its three rules.
* IMF parser (255-264): check whether `Time.parse_rfc1123`
  (time.iyi:2266) compiles; word the follow-up as "fix, then delete
  FileServer's helper".
* 16 MiB / 500 (201-211) is sound; no change.
* `MIME.with_charset(..., w)` (mime.iyi:28-31) builds in scratch then
  copies; fine, but do not imply no intermediate string.
