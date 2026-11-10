# Codebase details (egm-codebase-details)

Target: doc/drafts/fileserver-outgoing.md. No Blockers.

## Major

* D1 (158-163): "`Outgoing.new` appears only at 2452" is false. Also
  samples/ris/serve.ri:69 and test/ris/server_groups.ri:73, both into
  public `Server.format_response` (src/std/http.iyi:2444) and
  `format_head` (2419). A length check only in `answered_on_tape?`
  does not cover them. Check in `format_head`, or name the callers.
* D2 (132-137): missed reuse. `String::Builder#append_span` returns
  `String::Span` (src/iyi/tape.iyi:920-924; used at 3528-3570). Use
  it, or say (and probe) why a flat `Array(Int32)` is needed.
* D3 (255-264, 286-288): missed reuse. `Time.days_from_civil`
  (src/std/time.iyi:1784) should do the date math; say whether
  `digits?` duplicates `HTTP.content_length` (http_head.iyi:86).
  The accepted IMF bytes, weekday check and range checks are not
  specified.

## Nit

* Off-by-one cites: `as_tape` tape.iyi:214; `reserve` 895; Outgoing
  doc http.iyi:2213-2217; `LINES` 2220; Content-Length 2434-2438.
* http.iyi:2582-2584 is a doc comment; it also says the listener
  closes.
* `@text` can move: `grow` calls `RisRegion.owned_resize`
  (tape.iyi:902-917). Spans are offsets and survive; argue that.
* `seek` is an `IyiIO` reopening (src/std/file.iyi:2141-2162), not
  `File#seek`. `reserve(want)` is a total; right only on an empty
  body.
* fileserver.ri needs `import std/dir` (`Dir.tempdir`,
  dir.iyi:464). check.sh:1337/1358 run built binaries, not `ris run`.

## Verified

`header` 2246-2256 and refusal 2249-2251; `each_line` 2259-2265;
callers 2376, 2412; `MAX_CONNECTIONS` 2515-2517; `read_str` one fill
io.iyi:165-181; `File.open` file.iyi:28, 32-38; mime.iyi:28-31;
http_head.iyi:195-214; time.iyi:3635, 2776; fileserver.iyi cites;
check.sh:1187-1188; router.iyi:527; `truncate` tape.iyi:881.
Probes P1-P3a rest on runs and could not be checked read-only.
