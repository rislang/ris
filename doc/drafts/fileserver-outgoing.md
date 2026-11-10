# Draft: FileServer writes into the caller's Outgoing

Sixth draft, 2026-11-08, written beside its implementation. Five EGM
reviews are answered; the tables at the end map their items (reports
in doc/drafts/fileserver-review/ and -review-2/ to -review-5/).
Claims about the compiler and std cite file:line at 5b74fe0ff or a
probe, P1-P14 under Evidence. Probes ran on minitest, the 32-core build
server, against `make ris` at 5b74fe0ff.

## Terms

* *Tape*: ris's memory. Values go on the running scope's tape and are
  freed together when the scope ends; there is no heap and no GC
  (SPEC.md 1.1).
* *Scratch*: what a def makes for itself on the tape, freed when the
  def returns. A value made there cannot be returned or stored into
  something that outlives the def (SPEC 1.1, 1.9, 3.6).
* *View*: a `String` that points at bytes another value owns, nothing
  copied, valid only while that owner lives. `as_tape` on a `String`
  is the identity (src/iyi/tape.iyi:214): it marks a view, it copies
  nothing.
* `@[OnTape]`: a struct that lives on the tape and may hold views.
* `Field`: std/http's name-and-value pair of views
  (src/std/http_head.iyi:10).
* *Growth move*, *side region*: what `RIS_TAPE_STATS=1` counts when a
  growing value had to be moved or placed beside the tape. It prints
  counts, not times; both should be 0 (AGENTS.md "Fast on the tape").
* *iyi*: the language ris grew from. `.iyi` files are std modules both
  compilers read; `./bin/iyi` is iyi's compiler. ris programs are `.ri`.
* *Gate*: a check in `test/ris/check.sh`; a change lands only with all
  gates passing.
* *Now step*: the current section of TODO.md, "Now: code to the new
  SPEC" (TODO.md:38). At its end the tape ports are timed with
  *goose-evals*, ris-bench's `goose-evals.sh` benchmark run (AGENTS.md
  "Tape first").
* `Request`, `Response`: std/http's older server API, classes, built by
  `Server.serve`.
* `Incoming`, `Outgoing`: the tape API. `Server.answer` reads each
  request into an `Incoming` (views into the received bytes,
  http_head.iyi:195) and hands the block an empty `Outgoing`
  (src/std/http.iyi:2219) that the block fills: status, lines, body.
* *Answer*: one HTTP response; a *tape answer* is one built in an
  `Outgoing`.
* `MAX_CONNECTIONS`: the default of `Server.answer`'s
  `max_connections:` argument (http.iyi:2306, 2515-2517).
* Three lengths, kept apart: *`res.length`* is the `Content-Length` the
  server writes; *count* is the number of bytes FileServer sends (the
  file, or the range); *size* is the file's size.

## Problem

`std/fileserver` has one entry point:

```
FileServer.serve(root : String, req : Request,
                 index : String = "index.html") : Response
```

It does not compile on ris. Any program that calls it fails with:

```
src/std/fileserver.iyi:51: cannot return a value made in this def
`serve`'s scratch: it would have to be copied out (SPEC 1.9).
```

`Response` is a class. `serve` builds its header `Hash`, its texts and
its `File` in its own scratch and returns them inside the class; SPEC
1.9 lets only a String or a flat Array move down to the caller. No ris
gate calls the def (`bench/std_fileserver_exercise.iyi` runs on iyi;
`test/ris/std_text_plain.ri:41` only imports the module). ris-website's
`serve.ri` serves files itself, without ranges or caching.

The library rules (AGENTS.md "A library works on the caller's tape")
ask for the other shape: write into what the caller owns. For an answer
that is the `Outgoing`; its lines and body are on the request's tape and
are freed once the answer is written (http.iyi:2451-2460).

Two more findings shape the change. std/time's date parser does not
compile on ris either (Phase 1), and the compiler accepts a stored view
of an inline argument that then dangles (Prerequisite).

## Goals and non-goals

Goals:

* `FileServer.serve` compiles and runs on ris, under `Server.answer`.
* The answers the module doc promises stay (Behaviour lists the one
  deliberate change, the 304's lines).
* A gate calls it, so a compile error cannot come back unseen.
* `RIS_TAPE_STATS=1` counts 0 growth moves and 0 side regions while
  files are served.

Non-goals:

* Streaming a file to the socket without loading it (A2, Follow-ups).
* Porting `Router` to `Incoming`/`Outgoing` (Follow-ups).
* Changing ris-website (a separate repo; it moves after the merge).
* Fixing the compiler hole: this change files it with its gates and
  does not depend on it (Prerequisite).

## Prerequisite: inline arguments escape the store check

P1: a value built inline in an argument and stored by the callee as a
view is accepted, and the view dangles after the def returns. The same
value held in a local first is refused (P2).

P1 found five forms dangling, through today's `Outgoing#header(name,
value)` and a plain struct. Each printed foreign bytes (`ETag: ZZZZZZZ`,
`ETag: HTTP/1.1 200`) after a later def wrote scratch text. Each form is
one gate:

| P1 form | Def | Gate |
|---------|-----|------|
| `"<" + n.to_s + ">"` | top-level | `inline_view_concat` |
| `"<#{n}>"` | top-level | `inline_view_interp` |
| `n.to_s` | top-level | `inline_view_call` |
| `n.to_s` | instance method | `inline_view_instance` |
| `n.to_s` | `self` method | `inline_view_class` |

One `self`-method variant with two such lines was refused, so the check
is context-dependent. Where it misses
is not traced; the second review points at `tape_text`,
src/compiler/iyi/semantic/tape_shrink_checker.cr:514-548, whose first
line returns unchecked outside a `tape` block (:515).

This change does not wait for the fix: `Outgoing` copies every value
(below), so std/http and FileServer are safe whatever the checker
accepts. The copy stays after the fix; the local form is refused
anyway (P2).

### Phase 0: the TODO.md entry

Phase 0 adds this entry to TODO.md under "Known failures"
(TODO.md:220). Done when the entry is committed; the gates land in the
compiler fix's commit, so every phase stays green.

```
* Compiler: an inline argument stored as a view escapes SPEC 1.1/3.6.
  `k.put("<" + n.to_s + ">")`, where `put` stores `value.as_tape` in
  a field, compiles, and the field dangles once the def returns; the
  same value in a local is refused. Seen in Outgoing#header
  (doc/drafts/fileserver-outgoing.md, P1). Suspect: tape_text,
  src/compiler/iyi/semantic/tape_shrink_checker.cr:514-548. The fix
  commits five programs under test/ris/refused/ and their expect
  lines after check.sh:64:
    expect inline_view_concat 'cannot store data made in this def'
    expect inline_view_interp 'cannot store data made in this def'
    expect inline_view_call 'cannot store data made in this def'
    expect inline_view_instance 'cannot store data made in this def'
    expect inline_view_class 'cannot store data made in this def'
```

`test/ris/refused/inline_view_concat.ri`, in full:

```
# An inline argument stored as a view must be refused like a local.
module test/ris/refused/inline_view_concat

import std/int

@[OnTape]
struct Keep
  @texts : Array(String)

  def initialize
    @texts = Array(String).new(1) { "".as_tape }
  end

  def put(value : String) : Nil
    @texts[0] = value.as_tape
  end

  def first : String
    @texts[0]
  end
end

def fill(k : Keep, n : Int32) : Nil
  k.put("<" + n.to_s + ">")
end

# Scratch text written after fill returns lands where its value was.
def scribble(n : Int32) : Int32
  total = 0
  i = 0
  while i < 4
    s = "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ" + (n + i).to_s +
        "YYYYYYYYYYYYYYYYYYYYY"
    total = total + s.bytesize
    i = i + 1
  end
  total
end

def call(k : Keep) : Nil
  fill(k, 12345)
  scribble(7)
end

k = Keep.new
call(k)
scribble(9)
puts k.first.inspect   # today: "ZZZZZZZ", not "<12345>"
```

The other four differ only in the fill. `_interp` and `_call` change
`fill`'s line to `k.put("<#{n}>")` and `k.put(n.to_s)`. `_instance`
and `_class` replace `fill` with a struct and change its call in `call`:

```
struct Filler                      # _instance
  def fill(k : Keep, n : Int32) : Nil
    k.put(n.to_s)
  end
end
...
  Filler.new.fill(k, 12345)        # in call

struct Filler                      # _class
  def self.fill(k : Keep, n : Int32) : Nil
    k.put(n.to_s)
  end
end
...
  Filler.fill(k, 12345)            # in call
```

P13: today all five build with `ris build --no-codegen` and print
foreign bytes when run, so each `expect` line fails until the fix and
passes after it. Five files, not one: `expect` passes when a program is
refused at all (check.sh:43-52), so one program holding the five forms
would pass as soon as a partial fix refused any one of them.

### Other stored parameter views

Checked by grepping `as_tape` and stored parameters in std/http,
std/http_head and std/router:

* `Outgoing#header`: the only std/http API that stores a caller's
  value for later (http.iyi:2246-2256). This change copies it.
* `Incoming.new` (http_head.iyi:202) stores its arguments as views.
  std/http builds it from the request's own bytes (http.iyi:2368-2375,
  2410); a program that calls it with an inline value is exposed to the
  hole. Not changed here; the compiler fix covers it.
* `Router#handle` (src/std/router.iyi:550) keeps `Pattern.parse(text)`,
  and `Pattern` holds views of *text* (router.iyi:160-176, 202-208). An
  inline pattern string is exposed the same way. Router is on the old
  API and outside this change; the compiler fix covers it.

## Change

### The new entry point

```
FileServer.serve(root : String, req : Incoming, res : Outgoing,
                 index : String = "index.html",
                 max : Int64 = MAX_FILE) : Nil
```

`MAX_FILE` is 16 MiB (Helper signatures). The old def is removed, not kept
beside it (AGENTS.md: a replaced API goes). Use in a handler:

```
struct Handler
  def initialize(@root : String)
  end

  def call(req : Incoming, res : Outgoing) : Nil
    if req.path.starts_with?("/static/")
      return FileServer.serve(@root, req, res)
    end
    res.body << "{}"
  end
end
```

### Outgoing: header text lives in the answer

Today `header(name, value)` stores views of *name* and *value*
(http.iyi:2246-2256). A value the caller computes is refused when held
in a local (P2) and dangles when written inline (P1). Every line is now
copied into the answer's own text, and lines are spans of it.

New state, replacing `@lines`. The Array fields follow `Outgoing`'s
existing idiom (http.iyi:2223-2228): an `@[OnTape]` struct is passed by
value, so a field that a method changes is a slot in an Array the
copies share. The set length is a fourth slot of `@state`, not a field
of its own, so the change adds one growing value, not two (Memory).

```
@state : Array(Int32)        # [status, line count, 1 while a block
                             #  runs, res.length if set, else -1]
@spans : Array(String::Span) # name and value of each line
@text  : String::Builder     # the lines' bytes
```

`@spans` is made at full size, `LINES * 2` (64) spans, and written by
index, never pushed. `@text` is `String::Builder.new(1024)`.
`String::Span` (a start and a size, a flat value),
`String::Builder#append_span` (tape.iyi:919-924) and `String#[](span)`
(tape.iyi:524) exist and are reused.

```
# A header line, copied into this answer's own text.
def header(name : String, value : String) : Nil
  header(name) { |w| w << value }
end

# A header line whose value the block writes into the answer's own
# text, so a value made in the caller's def need not outlive it.
def header(name : String, & : String::Builder -> Nil) : Nil
```

The rules of the block form, in the order it applies them:

1. Called from inside another header block it raises "HTTP: a header
   inside a header block" (P8). The block's writer is the answer's own
   text, so a nested line would land inside the outer value.
2. With 32 lines written it raises "HTTP: more than 32 header lines".
3. `Content-Length`, `Connection` and `Transfer-Encoding` raise "is the
   server's own line", as today (http.iyi:2249-2251).
4. `@state[2]` is set to 1; the name is appended with `append_span`;
   the block writes the value; its span is the bytes written.
5. The name must be a token, the value free of line breaks and control
   characters; otherwise it raises with `Server.check_line`'s messages
   (http.iyi:2479-2483). A protected `Outgoing.refusal(text, name, value)`
   reads the two spans of `@text.to_s` and answers which rule failed;
   `header` raises the message. A refused line's bytes stay in `@text`,
   unreferenced, and `@state[2]` stays 1: the raise ends the request (a
   request panic closes the connection, per the comment at
   http.iyi:2582-2584), and nothing in std/http rescues it, so nothing
   reads either. Cutting `@text` back is refused by the compiler while
   the check's view is live (P3).
6. The two spans are stored; the count goes up; `@state[2]` is 0.

`each_line` (one caller, `format_head`, http.iyi:2428) yields
`Field.new(text[name], text[value])` with `text = @text.to_s`.

Spans are offsets, not views, so they stay right however `@text`
grows. On Linux and macOS a builder's reservation never moves
(src/iyi/region.iyi:523-525); on other targets `owned_resize` may move
it (tape.iyi:902-917) and a span is still right. P4 counts 0 growth
moves.

Cost: each value is copied once, at most 32 lines. It is not measured
on its own; goose-evals at the end of the Now step times the answer
path. Should that show the copy costing more than 1% of an answer, a
view-storing form returns for literals only, after the compiler fix.

### Outgoing: `res.length` for an answer to HEAD

```
# The Content-Length of an answer to HEAD, which sends no body.
def length=(count : Int64) : Int64   # raises "HTTP: not a length: N"
                                     # when count < 0 or > 2147483647
# The Content-Length format_head writes: the one set, else the body's.
def length : Int64
```

The contract is one rule: unless the answer is to HEAD, a set length
must equal the body's bytes, or writing the head raises "HTTP: length=
N with a body of M bytes; length= is for a HEAD answer" (P7). On an
answer to HEAD no body is sent and `res.length` is the line. A
bodiless status (1xx, 204, 304) writes neither line and is not checked
(http.iyi:2434-2438). The length is kept as an Int32: a body is at most
that (`read_str`, src/iyi/io.iyi:165).

The check sits in `format_head`, which every tape answer goes through:
`answered_on_tape?` (http.iyi:2455, the server's path, called from
2376 and 2412) and the public `format_response` (http.iyi:2444-2447,
called by test/ris/server_groups.ri:73-76 and
samples/ris/serve.ri:69-72). `format_head` gains the method:

```
def self.format_head(res : Outgoing, close : Bool,
                     head : Bool = false) : String
```

`format_response` passes its `head`; `answered_on_tape?` passes
`HTTP.same_name?(req.method, "HEAD")`. These are its only callers (the
other `format_head` takes a `Response`, http.iyi:3296).

### std/time: the HTTP-date parser compiles on ris

`Time::Format::HTTP_DATE.parse` is refused twice (P6): the parser's
`fail` stores a `TimeParseError` with an interpolated message in
`@error` (src/std/time.iyi:2774-2781), and each `parse` returns
`finish`'s answer from a parser in its own scratch. There are seven
such defs: `Format#parse` twice (time.iyi:2457, 2463) and the `parse`
of HTTP_DATE (3635), RFC_2822 (3656), ISO_8601_DATE (3671),
ISO_8601_DATE_TIME (3689) and ISO_8601_TIME (3704). The fix is about
40 lines, all in time.iyi, and P9 compiles it:

* `Parser` keeps `@why : String::Builder` and `@failed : Int32` (-1
  until a step fails) instead of `@error`. `fail(what)` writes the
  sentence into `@why` once; `refuse(what)` clears `@why`, writes its
  sentence and returns a `TimeParseError` viewing it (time.iyi:2785).
* `finish` builds the `TimeParseError` from `@why.to_s` when
  `@failed >= 0` (time.iyi:3529-3532).
* Each `parse` ends with one call, `Parser.new(string).<grammar>_answer`,
  where the new Parser method runs the grammar and ends with `finish`;
  SPEC 1.9 lets a def answer what the call it ends with answers. The six
  methods are `pattern_answer(pattern, offset, location)` (both
  `Format#parse` defs), `http_date_answer`, `rfc_2822_answer`,
  `iso_date_answer(offset)`, `iso_date_time_answer` and
  `iso_time_answer`.

P9: with the fix, all three RFC 9110 forms parse to 784111777 (the
example date of §5.6.7), a day 32 is a `TimeParseError` whose message
is intact after other scratch text is written ("1994-11 has days 1
to 30, not day 32 in ..."), `RFC_2822.parse` and `Format#parse` compile
too, and test/ris/time_tape_offset.ri passes. The RFC 850 two-digit
year follows §5.6.7's 50-year rule (`Parser.recent_year`,
time.iyi:3281-3286). The parser also accepts `UT`, `UTC` and offsets
where §5.6.7 says `GMT` (time.iyi:3056); that leniency is kept.

FileServer then reads `If-Modified-Since` with
`Time::Format::HTTP_DATE.parse(since.strip)`: a `Time` at or after the
file's modification second is a 304; a `TimeParseError` is ignored, as
§13.1.3 asks for an invalid date, and the answer goes on.

### Behaviour

Unchanged from the module doc (fileserver.iyi:1-25): GET and HEAD
only; the path percent-decoded and kept below *root*; a directory's
*index*; a 301 to the trailing `/`, the query kept; the type from
std/mime, `charset=utf-8` for text; `Last-Modified` and `ETag`; 304 on
`If-None-Match`, else `If-Modified-Since`; one `Range: bytes=` range as
206, suffix ranges included; 416 past the end; `If-Range`. Symbolic
links inside *root* are followed and may lead outside it, as before and
as Go's: *root* is trusted, the request path is not.

Changed: a 304 no longer carries `Content-Type` (RFC 9110 §15.4.5
lists what a 304 sends; the type is not among them). New: the cap and
its 500, the short-read 500, and their log lines.

### The order serve checks in

The first step that answers writes its own status, lines and body, and
returns; nothing after it runs.

1. Method not GET or HEAD: 405.
2. Path does not decode, does not start with `/`, holds NUL, backslash
   or a `..` segment: 404.
3. `File.info?` finds nothing: 404. A directory without the trailing
   `/`: 301. A directory: its *index*, `File.info?` again, 404 if
   missing. Not a regular file: 404.
4. Validators: ETag and Last-Modified from the stat. `If-None-Match`
   matches, or else `If-Modified-Since` is at or after the file: 304,
   whose lines (Last-Modified, ETag, Accept-Ranges) this step writes
   through `validators`. A 304 wins over the cap: it sends no body.
5. Range, on GET only and when `If-Range` names this version: past the
   end, 416; one range, *count* is its bytes; otherwise the whole
   file, *count* = size.
6. *count* over *max*: 500 and a log line, for HEAD too, so HEAD and
   GET agree.
7. GET with *count* > 0: `read_into`; a short read is a 500 with only
   its plain-text type, and a log line. HEAD: `res.length = count`. A
   GET of an empty file sends an empty body and sets nothing.
8. The 200 or 206: status, Last-Modified, ETag, Accept-Ranges,
   Content-Type, and for 206 Content-Range.

### Each answer

The lines are those FileServer writes; the server adds `Content-Length`
(not on 304) and `Connection` (http.iyi:2419-2441).

| Case | Status | FileServer's lines | Body |
|------|--------|--------------------|------|
| not GET/HEAD | 405 | Allow, Content-Type | `method not allowed\n` |
| bad path, missing | 404 | Content-Type | `not found\n` |
| dir without `/` | 301 | Location | empty |
| validator matches | 304 | Last-Modified, ETag, Accept-Ranges | none |
| past the end | 416 | Content-Range, Content-Type | `range not satisfiable\n` |
| over *max* | 500 | Content-Type | `file too large to serve\n` |
| file shrank | 500 | Content-Type | `file changed while read\n` |
| GET | 200 | Last-Modified, ETag, Accept-Ranges, Content-Type | file |
| GET range | 206 | the four, Content-Range | the range |
| HEAD | 200 | Last-Modified, ETag, Accept-Ranges, Content-Type | none |
| HEAD over *max* | 500 | Content-Type | none |

A HEAD over *max* runs the GET's step: FileServer writes the same body,
so `Content-Length` is its 24 bytes, and the server drops the body for
HEAD (http.iyi:2446, 2458).

At most 5 lines, under `Outgoing::LINES` (32, http.iyi:2220). The 405,
416 and 404 bodies are the old ones (fileserver.iyi:53, 104, 120).

### The cap, the read loop, a short read

*Cap.* *count* above *max* is a 500, so a range inside a large file is
still served. A *max* above `FileServer::MAX_BODY`, 120 MiB, is taken as
`MAX_BODY`. The body is `Outgoing`'s builder, made before serve runs, so
its reservation is the fixed 128 MiB (`SIDE_RESERVE`, region.iyi:529),
and a `reserve` past it ends the program with "tape side reservation
exhausted" (region.iyi:487-495) instead of answering. P14: with
`max:` 200 MiB, a 130 MiB file is a 500 and a log line, and a 100 MiB
and a 120 MiB file are read whole; without the clamp the 130 MiB file
ends the program with "tape side reservation exhausted: 268435456".
Below that ceiling `read_str`'s Int32 count (src/iyi/io.iyi:165) never
binds.

*Memory.* On Linux and macOS every growing tape value, a
`String::Builder` or an `Array`, reserves 128 MiB of address space, or
its first capacity if larger (region.iyi:367-370, 523-535;
tape.iyi:628-630, 1163-1166). Counted per answer on the fast path,
std/http's values and serve's own:

| Growing value | Today | This change |
|---------------|-------|-------------|
| `Outgoing@state` | 1 | 1 (two more slots) |
| `Outgoing@lines` / `@spans` | 1 | 1 |
| `Outgoing@text` | - | 1 (new) |
| `Outgoing@body` | 1 | 1 |
| `format_head`'s builder (http.iyi:2422) | 1 | 1 |
| the request's `fields` (http.iyi:2366, 2395) | 1 | 1 |
| serve's `to_rfc1123` (fileserver.iyi:103, time.iyi:2183) | - | 1 |
| HTTP_DATE's `@why`, on If-Modified-Since (time.iyi:2726) | - | 1 |
| per answer | 5, 640 MiB | 6 to 8, up to 1 GiB |

std/http's slow path (http.iyi:2408-2422) adds its own builder to
either column. The two rows of serve's are short-lived, freed when
serve returns, but they reserve while it runs. The cost is the
runtime's, not this change's: even a 128-byte builder reserves
128 MiB; TODO.md lists it.

At `MAX_CONNECTIONS` (1024) answers in flight that is 640 GiB of
address space today and up to 1 TiB after, whatever *max* is: this
change adds `@text`'s 128 MiB per answer, serve its two dates'. The
reservations are `MAP_NORESERVE` and
pages commit as they are touched (region.iyi:526), so what *max* bounds
is touched memory: at most 16 MiB of body per answer by default,
16 GiB at 1024 answers. With `vm.overcommit_memory=2` Linux ignores
`MAP_NORESERVE` and charges every reservation, up to 1 GiB per answer, so
such a host must run fewer connections; a smaller *max* does not help
there. Why 500, not 413: 413 is about the request's
content (RFC 9110 §15.5.14); here the server declines its own answer.

*Log lines.* Both 500s write one warning through std/log (P5):

```
Log.warn("fileserver: answer over max", path: path, bytes: count,
         max: max)
Log.warn("fileserver: file changed while read", path: path)
```

The first prints `... WARN - fileserver: answer over max --
path=/srv/big.bin bytes=2000 max=1000`. Logging is synchronous and an
entry borrows its text from the caller (log.iyi:23, 112-113); a backend
that keeps entries copies them (`RisMemoryBackend#write`, `copy_to`,
log.iyi:400-402), so a scratch-built *path* does not dangle (P10). The
block form `Log.warn { "...#{path}" }` is refused: its block becomes a
proc that may outlive *path*.

*Read loop.* `IyiIO#read_str(count, into)` returns after one buffer
fill (io.iyi:165-181), so it loops:

```
private def self.read_into(res : Outgoing, path : String,
                           start : Int64, count : Int64) : Bool
  want = count.to_i32
  body = res.body
  body.reserve(want)
  got = 0
  File.open(path) do |file|
    file.seek(start) if start > 0_i64
    while got < want
      n = file.read_str(want - got, body)
      break if n == 0
      got = got + n
    end
  end
  return true if got == want
  body.truncate(0)
  Log.warn("fileserver: file changed while read", path: path)
  res.status = 500
  text(res, "file changed while read\n")
  false
end
```

*Short read.* A file that shrank after the stat gives fewer bytes: the
body is dropped and the answer is that 500, never a partial 200 or 206
under the old size's ETag. Step 8 has not run, so the 500 carries no
validator and no file type.

*File close.* `File.open(path) do |file| ... end` closes the file in a
`defer` when the block ends (src/iyi/file.iyi:32-38). `seek` is
`File#seek(Int64)` (src/std/file.iyi:2150). A file removed
between stat and open raises "cannot open" (src/iyi/file.iyi:28); the
server's doc says a request panic closes the connection and replaces
the worker (http.iyi:2582-2584). The old def raised there too.

### Helper signatures

```
import std/http::{HTTP, Incoming, Outgoing}
import std/uri::{URI}
import std/mime::{MIME}
import std/file::{File}
import std/time::{Time}
import std/log::{Log}

MAX_FILE = 16_777_216_i64     # in FileServer, the default *max*
MAX_BODY = 125_829_120_i64    # the largest *max* honoured

private def self.read_into(res : Outgoing, path : String,
                           start : Int64, count : Int64) : Bool
private def self.validators(res : Outgoing, status : Int32,
                            tag : String, stamp : String) : Nil
private def self.text(res : Outgoing, body : String) : Nil
private def self.not_found(res : Outgoing) : Nil
protected def self.tag_listed?(list : String, tag : String) : Bool
protected def self.range_applies?(req : Incoming, tag : String,
                                  stamp : String) : Bool
def self.byte_range(value : String, size : Int64)
    : {Int64, Int64} | Bool | Nil
```

`tag_listed?` and `byte_range` are unchanged; `range_applies?` takes
`Incoming` (same `method` and `header` calls, http_head.iyi:195-207).
`text` writes the plain-text type and appends to `res.body`. The
`headers["Content-Length"]` line (fileserver.iyi:112) goes: the server
writes it and `header` refuses it. The ETag and the date stamp are
built in serve's scratch and passed to `header`, which copies them. The
type goes in as `res.header("Content-Type") { |w|
MIME.with_charset(MIME.from_extension(path), w) }`, std/mime's writer
form (src/std/mime.iyi:28).

### New doc comments

Module doc, replacing fileserver.iyi:1-3 and 13-14:

```
# Files served from a directory: what a `Server.answer` block writes
# into its `Outgoing` with `FileServer.serve(root, req, res)` for the
# requests it means to be files. Go's `http.FileServer`, and the same
# RFC 9110 rules.
...
# The file, or its range, is read whole into the answer's body on the
# request's tape, up to *max* bytes (16 MiB by default, at most
# `MAX_BODY`); above it the answer is a 500 and a log warning. A HEAD
# reads nothing and states the length.
```

The def's doc, replacing fileserver.iyi:36-37 and 49-50:

```
# Answers *req* into *res* from the files under *root*: what a
# `Server.answer` block calls to serve a directory. ...
# ... The file is read into `res.body` whole, so an answer of more
# than *max* bytes is a 500 and a log warning; *max* is honoured up to
# `MAX_BODY`, and a file larger than that is not served from memory.
```

`Outgoing`'s doc (http.iyi:2213-2217) replaces "The lines go in slots
made at their final size, so the body's writer is the one value that
grows." with: "Each line is copied into the answer's own text, so a
value made in the block's def need not outlive it; `header(name) { |w|
... }` writes a computed value there directly. `length=` states the
length of an answer to HEAD, which sends no body."

## Alternatives

A1. Keep `Response` and copy it out (`copy_to(owner)` before
returning). Refused: serve has no owner to name, the caller would pass
one, and every answer would be copied. It keeps the API the library
rules replace.

A2. Stream first: a file body on `Outgoing`, e.g.
`res.file(path, start, count)`, sent after the head with `sendfile`.
It removes the cap and the memory peak. Not first: ris's std has no
sendfile (none in src/std or src/iyi; src/socket.cr:372 is Crystal's
inherited socket, which ris programs do not reach), and it changes the
write path of `answered_on_tape?`. Callers would not change.

A3. Keep the old def beside the new one. Refused: it does not compile,
and AGENTS.md removes a replaced API.

A4. Leave file serving to each program (what ris-website does).
Refused: each program loses ranges, validators and the path checks.

A5. A `Server.answer` variant that takes a file. The work of A2 with a
second entry point.

A6. Keep `header(name, value)` storing views, spans only for the block
form (the second draft). Dropped: it leaves the P1 hole open through
std/http's most used call.

A7. A private three-form date parser in FileServer (the third draft).
Dropped: P9 shows std/time's fix is about 40 lines of the same
scratch-escape kind, and every std/time parser user gains it;
src/std/mail.iyi:1052 already copies `days_from_civil` for the same
reason; a third copy is not wanted.

## Risks and mitigations

* Path traversal: the old checks, unchanged; Tests case 15.
* The file changes between stat and read. Shrinking: the 500. Growing:
  only *count* bytes are read, the size the ETag names. Removal: a
  raise that closes the connection.
* Memory: touched memory is at most *max* per answer in flight; address
  space is six to eight 128 MiB reservations per answer while serve
  runs, against five today (see Memory). Strict overcommit hosts run
  fewer connections.
* A file over `FileServer::MAX_BODY` cannot be served at all until A2.
* A HEAD over the cap is a 500, so a client that sends HEAD to learn
  the size before resuming with ranges sees no size. Mitigation: the
  log line names the path and *count*; a range GET still works (Tests
  case 18); A2 removes the cap.
* A GET handler that sets `length=` by mistake raises before writing;
  a wrong `Content-Length` never reaches the wire (P7).
* Header bytes of a refused line stay unreferenced in `@text` until the
  request ends.
* The std/time change touches every date parse: its messages change
  storage, not wording (P9 reads one back), time_tape_offset.ri stays
  a gate, and the two programs that failed before fail the same way
  (P11).
* The compiler hole bites other APIs that store a parameter's view
  (`Incoming.new`, `Router#handle`); its five gates land with the fix.

## Files and phases

Phase 0, the TODO.md entry above, under "Known failures". Done when it
is committed. The five gate programs are not in the tree until the fix.

Phase 1, std/time, one commit, gated on its own:

* src/std/time.iyi: `@why`, `@failed`, `fail`, `refuse`, `finish`, the
  six `_answer` methods, and the seven `parse` defs ending in one.
* test/ris/time_http_date.ri: new. The three forms of §5.6.7's example
  date parse to 784111777; `Sun, 32 Nov 1994 08:49:37 GMT` and
  `garbage` give a `TimeParseError` whose message is read after other
  scratch text is written ("... not day 32 in ..." and `"garbage" is
  not a day name at byte 0 of "garbage"`); `RFC_2822.parse` of the same
  instant. PASS line `PASS: HTTP dates parsed on the tape`. Its
  check.sh block follows time_tape_offset's (check.sh:843-849):

  ```
  # std/time's parsers answer from their own scratch: HTTP dates, RFC 2822.
  out=$("$RIS" run test/ris/time_http_date.ri 2>&1)
  if [ "$out" = 'PASS: HTTP dates parsed on the tape' ]; then
    echo "runs     time_http_date"
  else
    echo "FAILED   time_http_date: $out"; status=1
  fi
  ```

Phase 2, std/http, one commit, gated on its own:

* src/std/http.iyi: `Outgoing` with `@spans`, `@text`, a four-slot
  `@state`, both `header` forms copying, `Outgoing.refusal`, `length=`,
  `length`, `each_line` from spans;
  `format_head(res, close, head)` with the length check; its two
  callers pass `head`. Doc as above.
* test/ris/answer.ri: one more request, `HEAD /len`, whose handler
  sets `res.length = 7` and writes a block header; the expected text
  gains that answer. Its PASS line is unchanged.
* test/ris/outgoing_refusals.sh: new. `expect` only builds, and these
  refusals are raised at run time, so the script writes four programs
  into a `mktemp -d` directory (heredocs, removed on exit) and runs
  each with `"$RIS" run`. A case passes when the run exits non-zero,
  its output holds the message, and the program never prints
  `reached`, its line after the call:

  | Program | Does | Message, after `HTTP: ` |
  |---------|------|---------|
  | `length_body` | 3 bytes, `length = 9` | `length= 9 with a body of 3 bytes` |
  | `length_negative` | `length = -1` | `not a length: -1` |
  | `header_nested` | header in a block | `a header inside a header block` |
  | `header_break` | `a\r\nInjected: 1` | `header B contains a line break` |

  `length_body` writes through `format_response`; `header_break`'s
  block writes the value of a line named `B`.

  With every case passing it prints `PASS: length= and block headers
  refused` and exits 0. Its check.sh block follows `answer`'s:

  ```
  # Outgoing's length= and block-header refusals, raised at run time.
  out=$(RIS="$RIS" bash test/ris/outgoing_refusals.sh 2>&1)
  if [ "$?" -eq 0 ] &&
      [ "$out" = 'PASS: length= and block headers refused' ]; then
    echo "runs     outgoing_refusals"
  else
    echo "FAILED   outgoing_refusals: $out"; status=1
  fi
  ```

Phase 3, std/fileserver, one commit, gated on its own:

* src/std/fileserver.iyi: the new serve and helpers, new doc.
* test/ris/fileserver.ri: new, see Tests; its check.sh block (Tests)
  follows `outgoing_refusals`'s.
* bench/std_fileserver_exercise.iyi and .sh: removed. The .iyi drives
  the old `Server.serve` with `call(req) : Response` (bench
  .iyi:56-131) and runs on `./bin/iyi`; the .sh greps a literal source
  line (bench .sh:199). Its cases move to fileserver.ri.
  bench/std_siblings.sh:46 is a size table and keeps its line.
* src/std/router.iyi:527: the example line becomes two comment lines,
  "# Files: call FileServer.serve(root, req, res) from a Server.answer
  # block; Router is not ported to Outgoing yet."
* test/ris/std_text_plain.ri:41 keeps its import (it checks that std
  modules compile; P4 imports and calls the new module).
* UPSTREAM.md: no entry. `Outgoing` is ris-only (`@[OnTape]`), and the
  std/time fix is a tape rule (SPEC 1.9), so both stay in ris.

## Tests

`test/ris/fileserver.ri`, driven like test/ris/answer.ri: a loopback
socket, `Server.answer` with `max_connections: 1`, the requests
pipelined on one connection, the last with `Connection: close`, the
reply compared with one expected text, PASS line
`PASS: files answered into Outgoing`. It imports std/socket, std/http,
std/fileserver, std/file, std/dir (`Dir.tempdir`, `Dir.mkdir_p`,
`Dir.delete`, src/std/dir.iyi:464, 590, 637), std/time, std/random and
std/log. The directory is `Dir.tempdir + "/ris_fileserver_"` plus
`Random::Secure.hex(6)`, made at start and removed at the end file by
file (`FileUtils.rm_rf` does not compile on ris: its recursion holds a
growing temporary, file_utils.iyi:314). One more request with
`Connection: close`, a GET of a.txt, ends the run. Files: `a.txt`
(`hello world`), `sub/index.html`, `nodir/` (no index), `empty.txt`,
`big.bin` (2000 bytes; the handler passes `max: 1000_i64`). The
expected ETag and
Last-Modified are built from `File.info?` of each file.

1. GET a.txt: 200, the four lines, body.
2. HEAD a.txt: 200, `Content-Length: 11`, no body.
3. If-None-Match with the tag, with `W/` and the tag, with `*`: 304
   each; another tag: 200.
4. If-Modified-Since in the future, written as the literals
   `Fri, 01 Jan 2100 00:00:00 GMT`, `Friday, 01-Jan-60 00:00:00 GMT`
   (2060 by the 50-year rule) and `Fri Jan  1 00:00:00 2100`: 304 each;
   `Thu, 01 Jan 1970 00:00:00 GMT`: 200.
5. Invalid dates, `Fri, 32 Jan 2100 00:00:00 GMT` and `garbage`: 200.
6. Range `bytes=2-4`: 206 `bytes 2-4/11`, `llo`.
7. Suffix `bytes=-3`: 206 `bytes 8-10/11`, `rld`.
8. `bytes=99-`: 416 `bytes */11`.
9. `bytes=0-1,3-4`: 200, the whole file.
10. If-Range with the tag and a range: 206; another tag: 200.
11. HEAD with a range: 200 (ranges are for GET).
12. `/sub?q=1`: 301 `Location: /sub/?q=1`.
13. `/sub/`: 200, the index, `text/html; charset=utf-8`.
14. `/nodir/`: 404.
15. `/../a.txt`, `/a%00.txt`, `/a%5c.txt`: 404 each.
16. POST: 405 with `Allow: GET, HEAD`.
17. empty.txt: 200, `Content-Length: 0`.
18. big.bin: GET 500 `file too large to serve`; HEAD 500,
    `Content-Length: 24`, no body;
    `If-None-Match: *` 304 (the 304 wins); `Range: bytes=0-9` 206.

The test sets `Log.setup(Severity::Info, RisMemoryBackend.on_program)`
first, so warnings stay out of the compared reply, and after the reply
checks that `output` holds the two over-max warnings of case 18 with
`path=` ending `/big.bin` and `bytes=2000`. The short-read 500 is not
driven (it needs a file truncated between stat and read); `read_into`
is reviewed instead.

The check.sh block:

```
out=$("$RIS" run test/ris/fileserver.ri 2>&1)
if [ "$out" = 'PASS: files answered into Outgoing' ]; then
  echo "runs     fileserver"
else
  echo "FAILED   fileserver: $out"; status=1
fi
stats=$(RIS_TAPE_STATS=1 "$RIS" run test/ris/fileserver.ri 2>&1 |
  grep '^ris tape: ')
case "$stats" in
  *' 0 growth moves '*' 0 side regions '*)
    echo "runs     fileserver tape" ;;
  *) echo "FAILED   fileserver tape: $stats"; status=1 ;;
esac
```

## Follow-ups (not this change)

* The compiler fix for P1, with its five gates (Phase 0's entry).
* A2, a streamed file body, once ris's std has sendfile.
* Port `Router` to `Incoming`/`Outgoing`, then restore its example.
* ris-website's `serve.ri` calls `FileServer.serve`.

## SPEC

No SPEC rule changes: std/http, std/time and std/fileserver are made
to follow SPEC 1.1 and 1.9. P1 is the compiler failing SPEC 1.1/3.6 as
written. No SPEC_CHANGELOG entry is needed.

## Evidence

All on minitest at 5b74fe0ff. "Patched" means copies of std/http,
std/time and std/fileserver in a scratch directory ahead of `src` on
`IYI_PATH`; src/ was not changed. P13 ran on unpatched std; P14 on the
implemented tree.

* P1, the hole, unpatched std. The `Keep` program above prints
  `"ZZZZZZZ"`. Through `Outgoing#header` and `format_head`: the five
  forms in a top-level def, `n.to_s` in an instance and a `self`
  method, each printing foreign bytes. A `self` method with two such
  lines was refused.
* P2: `s = ...to_rfc1123; res.header("Last-Modified", s)`: refused,
  "cannot store data made in this def where it outlives the def".
* P3: cutting `@text` back on a refused line: refused, "cannot shrink
  tape storage with a live view of Std::Http::Outgoing.@text".
* P4: patched. The P1 `Outgoing` probes print `ETag: "12345"` and
  `ETag: 12345`. The new serve behind `Server.answer`, 20 requests, a
  subset of Tests (cases 1, 2, 4, 5 without `garbage`, 6, 7, 8, 12,
  13, `..` of 15, 16, 17, 18): every status as listed;
  `RIS_TAPE_STATS=1`: 0 growth moves, 0 side regions.
  test/ris/answer.ri and test/ris/server_groups.ri pass.
* P5: `Log.warn(msg, path:, bytes:, max:)` in serve compiles and
  prints the line above; `Log.warn { ... }` is refused.
* P6: unpatched `HTTP_DATE.parse`: refused at time.iyi:3635; with only
  the message un-interpolated, refused at time.iyi:2776 and then at
  each interpolated `fail` call (time.iyi:2938 first).
* P7: a 3-byte body with `length = 9`, through `format_head`: panics
  "HTTP: length= 9 with a body of 3 bytes; length= is for a HEAD
  answer". `length = -1`: panics "HTTP: not a length: -1".
* P8: a header inside a header block: panics "HTTP: a header inside a
  header block". `res.header("B") { |w| w << "a\r\nInjected: 1" }`,
  a line named `B`: panics "HTTP: header B contains a line break".
* P9: patched std/time. The three forms give 784111777; day 32 gives
  the message quoted above, read after scratch was written;
  `RFC_2822.parse` gives 784111777; `Format.new("%Y-%m-%d").parse`
  compiles and answers its "names no time zone" error;
  time_tape_offset.ri passes. Through serve (P4 rerun with it): the
  three future dates 304, day 32 200.
* P10: `Log.warn` with a scratch-built path in a def, the def returns,
  scratch is written, then `RisMemoryBackend#output`: the line reads
  `path=/srv/42/big.bin`, intact.
* P11: test/ris/borrowed_text.ri and test/ris/cookie.ri fail the same
  way with and without the std/time patch (neither is a `ris run`
  gate; borrowed_text runs under `heap_trap`, check.sh:972, which
  passes on a trap, a compile-time refusal or a clean run).
* P12: in the third draft's private parser, `text[4] == ' '` compiled
  and was always false (a String against a Char); the parser is gone,
  noted here for whoever writes byte checks.
* P13: the five `inline_view_*` programs of Phase 0, unpatched std:
  each builds with `ris build --no-codegen` and prints foreign bytes
  (`"ZZZZZZZ"` for `_concat`, escaped scratch bytes for the other four)
  where `"<12345>"` or `"12345"` belongs.
* P14: the implemented serve, called with `max: 209_715_200_i64` on
  sparse files: 130 MiB is a 500 with the log line `bytes=136314880
  max=125829120`; 100 MiB and 120 MiB are 200s with the whole body.
  With the clamp removed, 130 MiB ends the program: "iyi: tape side
  reservation exhausted: 268435456".

## First review, items

| Item | Summary | Where |
|------|---------|-------|
| B1 | values made in scratch | Outgoing: header text lives in the answer |
| B2 | read loop, cap, short read | The cap, the read loop, a short read |
| B3 | open questions | decided: `res.length`, cap, Router (Files) |
| B4 | no alternatives | Alternatives |
| M1 | HEAD reads the file | Outgoing: `res.length` for an answer to HEAD |
| M2 | memory peak | The cap, the read loop, a short read; A2 |
| M3 | file list, phases | Files and phases |
| M4, M11 | the bench; std_text_plain | Files and phases |
| M5 | test plan | Tests |
| M6 | stale doc comments | New doc comments |
| M7 | helper signatures | Helper signatures |
| M8 | goals, risks | Goals and non-goals; Risks and mitigations |
| M9 | undefined terms | Terms |
| M10 | File never closed | The cap, the read loop, a short read |

## Second review, items

| Item | Summary | Where |
|------|---------|-------|
| MA1 | check misses a writer | Outgoing: `res.length` ...; Phase 2 |
| MA2 | block rules, Span | Outgoing: header text lives in the answer |
| MA3 | inline arguments | Prerequisite; P1, P4 |
| MA4 | three date forms | std/time: the HTTP-date parser ... |
| MA5 | check order | The order serve checks in; Tests case 18 |
| MA6 | terms, table targets | Terms; these tables |
| MA7 | the length= contract | Outgoing: `res.length` ... |

## Third review, items

| Item | Summary | Where |
|------|---------|-------|
| MB1 | private date parser | std/time: ...; Phase 1; A7; P6, P9 |
| MB2 | parked gate's home | Phase 0: the TODO.md entry |
| MB3 | gate one form; other views | Phase 0; Other stored parameter views |
| MB4 | Log test dangling | Log lines; P10 |
| MB5 | cap memory figure | The cap ... (Memory) |
| MB6 | 304 lines, P range, terms | The order serve checks in; Terms |
| Nits | idiom, rules, citations | throughout |

## Fourth review, items

| Item | Summary | Where |
|------|---------|-------|
| M1 | memory figure | The cap, the read loop, a short read (Memory); Risks |
| M2 | *max* above 128 MiB | The cap, the read loop, a short read (Cap); P14 |
| M3 | gates green today? | Prerequisite: inline arguments escape ...; P13 |
| M4 | outgoing_refusals.sh | Files and phases (Phase 2) |
| Nits | doc, rules, citations | throughout |

## Fifth review, items

| Item | Summary | Where |
|------|---------|-------|
| M1 | serve's own reservations | The cap ... (Memory); Risks; TODO.md |
| Nits | 40 lines, refusal, MAX_BODY | throughout |
