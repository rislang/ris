# Draft: Server.answer serves what Server.serve serves

Second draft, 2026-11-10. One EGM review (design, readiness,
zoom-out, codebase details) is folded in; its items are mapped at the
end. Decision (user, 2026-11-10): HTTP handlers move from `def
call(req) : Response` to `call(req : Incoming, res : Outgoing) : Nil`;
`Server.answer` grows what handler benches need today. The old form
stays refused; there is no adapter from it.

## Terms

* `Server.serve(host, port, config, Handler, ...)`: the old pool
  (src/std/http.iyi:2690; the refused open-socket form at :2699;
  options documented at :2628-2689). Its handler answers a `Request`
  with a `Response` (classes, header `Hash`es). It has TLS, HTTP/2,
  compression, streamed bodies and upgrades.
* `Server.answer(host, port, config, Handler, max_connections)`: the
  tape pool (http.iyi:2399). Its handler reads an `Incoming` (views of
  the received bytes, src/std/http_head.iyi:195) and writes an
  `Outgoing` (status, up to 32 header lines, a body builder,
  http.iyi:2259). Today it serves cleartext HTTP/1.1 only.
* *Port set*: every file that defines or calls a server-side
  `Request -> Response` form (`git grep ': Response'`):
  * benches: http2_exercise, std_acme, std_autocert, std_cookie,
    std_fuzz (`Server.handle` with a proc, :2087), std_http_exercise
    and its .sh, std_http_https_records, std_http_latency,
    std_http_resume, std_http_server, std_http_stop, std_router,
    std_sse, std_websocket; each bench's `RisExerciseServer.serve`
    wrapper calls `Server.serve` and moves too;
  * samples/iyi/autocert.iyi;
  * tests: test/ris/http_conn_growth, http2_conn_growth, http_coding,
    http_keepalive_scope, http_open, http_prefork_tls, http_continue,
    websocket_handshake, sse_open;
  * std: router.iyi, acme.iyi (`answer`, :911), autocert.iyi (:666),
    sse.iyi, websocket.iyi.

## What the port set needs

| feature                   | used by                                   |
|---------------------------|-------------------------------------------|
| TLS (`tls_config`), ALPN  | http2, acme, autocert, https_records,     |
|                           | latency, resume, stop, websocket, sample  |
| HTTP/2 (ALPN `h2`, h2c)   | http2, latency, resume, stop,             |
|                           | http2_conn_growth                         |
| compress                  | http2, http_exercise, http_server,        |
|                           | http_coding                               |
| streamed answer, SSE      | http2, http_exercise, latency,            |
|                           | http_server, sse, sse_open                |
| file (IyiIO) answer       | http_exercise                             |
| streamed request body     | http_exercise, fuzz (`body_io`)           |
| upgrade, WebSocket        | http2, http_exercise, stop, websocket,    |
|                           | websocket_handshake                       |
| Router, ACME challenge    | router, acme, autocert, sample            |

## Design

`Server.answer` takes `Server.serve`'s options and runs its connection
code; nothing is built as a `Request` or `Response` for a handler.
`Server.serve(host, port, ...)` is then removed: one entry point.

### Options

    Server.answer(host, port, config, Handler,
                  stream_bodies : Bool = false, compress : Bool = false,
                  timeout_ms : Int32 = 60000,
                  request_timeout_ms : Int32 = REQUEST_TIMEOUT,
                  max_connections : Int32 = MAX_CONNECTIONS) : Nil

No new plumbing: `prefork`, `supervise` and `run_worker` already
carry these four (http.iyi:2712-2827); `answer` stops passing the
constants `false, false, 60000, REQUEST_TIMEOUT` (:2402). TLS is the
handler's optional `tls_config`, read once per worker (:2803).
`listening(port)` is kept.

`run_worker`'s `{% if S == Incoming %}` (:2816) picks:

* `tape_connection` (the fast path: requests read where they lie)
  for cleartext with neither *stream_bodies* nor *compress*;
* `handle` otherwise, which does TLS and then `serve_h1`/`serve_h2`.

The fast path takes *timeout_ms* and *request_timeout_ms* in place
of its hard-coded 60000 (:2413, :2419, :2439). It checks HTTP/2's
preface first (`h2_preface?`) and hands such a connection to
`serve_h2`, with `remote` from the socket and no peer certificates
(cleartext). It keeps HTTP/1.0 and chunked requests on its slow branch
(:2440), as today, so the speed gates measure what they measure now.

The fast path supports `stream`, `send` and `upgrade` (below): the
server cannot know before the handler runs, and the SSE and two
WebSocket handlers serve cleartext without either option. A plain
answer still goes out as one write; only a streamed one writes the
head first.

### One request path, two answer types

`serve_h1`, `serve_h2_request`, `answered?`, `send_source`,
`send_stream`, `taken_over`, `coding_for`, `compressed` and
`H2Connection#answer` (:7706) take `Request`/`Response` today. They
are rewritten to take `Incoming`/`Outgoing`, not duplicated: once the
port set is moved no caller of the old types remains on the server
side. `Response` stays as the client's answer type.

Building `Incoming` on these paths: `serve_h1` reads the head with
`HeadParser.parse_head` into an `Array(Field)` on the request's tape,
as `tape_connection` does (:2490), not `request_head`'s `Hash`;
HTTP/2's `request_head` (HPACK) fills the same `Array(Field)` in
order, duplicates kept. The pseudo-headers give method, path and
query.

### Incoming

`Incoming` gains what `Request` gave handlers:

* `version : String` ("HTTP/1.1", "HTTP/1.0", "HTTP/2").
* `remote_address : String?`, `tls_resumed? : Bool`,
  `peer_certificates : Array(Certificate)`.
* `body_io : BodyReader`: under *stream_bodies* the body is read from
  it and `body` is empty; without it `body_io` reads the whole body
  already in `body`.

`BodyReader` and `Certificate` live in http.iyi and std/tls, so
`Incoming` moves into http.iyi (http_head keeps `HeadParser`,
`Field`, `ParsedHead`); the alias at http.iyi:160 goes. `header(name)`
exists (http_head:206).

### Outgoing

The block writes status, headers and `body` as today. State lives in
`@state`, the slot array copies share (:2265), grown from 4 to 6
slots: [4] how the answer ends (0 whole, 1 stream, 2 send, 3
upgrade), [5] 1 when `close` is asked. The sink is a reference
(a class) set once by the server, so copies share it too.

* `res.stream { |w : BodyWriter| ... }`: writes the head now (chunked
  over HTTP/1.1, DATA frames over HTTP/2, to the close for HTTP/1.0),
  runs the block, ends the body. A HEAD runs no block.
* `res.send(io : IyiIO)`: the same, copying *io* to its end.
  `FileServer` (src/std/fileserver.iyi:66, `read_into` :158) keeps
  reading small files into `body`; `send` is for a body larger than
  is worth holding, as `Response.new(status, io)` was.
* `length=` before `stream`/`send`: the head says `Content-Length`,
  and the body must have that many bytes. Fewer or more closes the
  connection (HTTP/1.1) or resets the stream with RST_STREAM
  (HTTP/2). Without `stream`/`send`, `length=` is still for a HEAD
  answer alone (:2534).
* `res.upgrade`: sets the 101 and [4] = 3, nothing else. After `call`
  returns, inside the request's tape block, the server writes the 101
  with the block's headers and calls the handler's
  `take_over(socket : IyiSocket | TlsStream, leftover : String,
  res : Outgoing)`, as `taken_over` does today (:2948-2955, :3101).
  The request's tape block ends after `take_over` returns, so `res`
  and its views live through it. HTTP/2 answers an upgrade 501 on
  its stream (RFC 8441's WebSocket over HTTP/2 is not planned).
* `res.close`: the connection closes after this answer.
  `Connection` stays the server's own line (:2302).
* `res.header(name) : String?` reads a line back, for
  `WebSocket.serve` and the coding choice.

A block that raises inside `stream`/`send` after the head was written
closes the connection (HTTP/1.1) or resets its stream (HTTP/2): the
client sees a cut body, never a second head.

An `Outgoing.new` a test makes has no sink: `stream`/`send` raise
"HTTP: this Outgoing is not a server's".

### Compile-time and runtime refusals

* `def call(req) : Response`, any server form: refused by name, as
  now, pointing at `call(req : Incoming, res : Outgoing) : Nil`.
* `res.upgrade` in a handler without `take_over`: a compile error
  (`responds_to?` in a macro check of `F`), naming `take_over`.
* A second end (`stream`, `send`, `upgrade` after one of them), or
  `stream`/`send` after `body` was written: a runtime raise. The
  compiler cannot see the order across branches and defs; the
  message names the safe form, "write the body inside stream, or
  only into body".

### Compression

`coding_for(accept : String?, res : Outgoing) : String?` replaces the
`Request, Response` form (:3201): the request's `Accept-Encoding` and
the answer's type, coding, status and end kind. When the server codes
a body it writes `Content-Encoding` and `Vary: Accept-Encoding` in
the head writer itself, beside `Content-Length`; these server lines
do not count against `LINES`, and a block's own `Content-Encoding`
means the server does not code. A whole body of `COMPRESS_FROM` bytes
or more goes zstd or gzip into one builder sized at the body's length
up front (no growth moves); `stream`/`send` go gzip through
`Deflater` as today.

### Std modules

* `SSE.stream(res : Outgoing) { |events : EventWriter| ... } : Nil`:
  200, `text/event-stream`, `Cache-Control: no-cache` unless the
  block wrote one first; headers come from `res.header`, not a
  `Hash`. Then `res.stream`.
* `WebSocket.upgrade(req : Incoming, res : Outgoing, protocols =
  [] of String, deflate = true) : Nil`: the 101's headers and
  `res.upgrade`, or a 400/426 answer. `WebSocket.serve(socket,
  leftover, res : Outgoing, ...)` reads the agreed extension with
  `res.header`. The block-form refusal (websocket.iyi:512) stays,
  reworded for the new signature.
* `Router`: `handle(pattern) { |req, res, params| ... }` with a
  `Proc(Incoming, Outgoing, Hash(String, String), Nil)`, `call(req,
  res) : Nil`; 404/405 (with `Allow`), `redirect` and `plain` write
  into `res`. router.iyi:528's "not ported" note goes.
* `Acme#answer(req : Incoming, res : Outgoing) : Bool` and the same on
  `Autocert`: true when the request was an HTTP-01 challenge and was
  answered.
* `Cookie`'s `Response` readers are the client's and stay.

## Tape

A request's tape block (`serve_h1`, `serve_h2_request`, the fast
path's inner block) holds the `Incoming`, the `Outgoing`, its sink
and any coded copy; all go when the answer is written or `take_over`
returns. A `stream` block's writes go to the socket as they come.

## Gates

New tests in test/ris/, each under `check.sh`:

* answer_tls.ri: TLS 1.3 handshake, an answer, `tls_resumed?`.
* answer_h2.ri: HTTP/2 over TLS (ALPN) and cleartext prior knowledge
  on the fast path; whole, streamed and 413 bodies; upgrade 501.
* answer_compress.ri: gzip and zstd by `Accept-Encoding`, none under
  `COMPRESS_FROM`, a stream gzip, the block's own coding kept.
* answer_stream.ri: `stream` chunked and with `length=` (right and
  short), `send` of a file, HEAD, HTTP/1.0 to the close,
  `stream_bodies` `body_io`, a raise mid-stream.
* answer_timeout.ri: the fast path honours both timeouts.
* answer_upgrade.ri: echo over `take_over`; WebSocket over `wss://`;
  SSE events; Router 404/405/redirect; an ACME challenge answered.
* refused/: `upgrade` without `take_over`; the old `call` form.

Then the whole port set moves and passes as before.

## Decision on the open question

The user decided (2026-11-10): Router, Acme and Autocert's server
side move to `Incoming`/`Outgoing` in 0.1.0. The old `Request`/
`Response` server forms and `Server.serve` are removed; nothing is
kept beside them (AGENTS.md: a dropped form is removed).

## Review map (first EGM round)

| item                                       | answer             |
|--------------------------------------------|--------------------|
| port set incomplete (fuzz, https_records,  | Terms: port set    |
| tests, router, acme, autocert)             |                    |
| fast path cannot stream/upgrade            | fast path supports |
|                                            | them               |
| fast path ignores timeouts                 | Options, a gate    |
| "only types differ" understated            | One request path   |
| Hash vs Field on handle path               | Field arrays       |
| Outgoing state layout, `length=` meaning   | Outgoing           |
| coding_for signature, Vary, LINES          | Compression        |
| upgrade timing, tape lifetime              | Outgoing, Tape     |
| raise mid-stream; h2 wrong length          | Outgoing           |
| runtime vs compile refusals                | Refusals           |
| prefork already carries options            | Options            |
| FileServer overlap                         | Outgoing `send`    |
| h2 upgrade: 501 or RFC 8441                | 501, 8441 not      |
|                                            | planned            |
| serve kept or removed                      | removed            |
| HTTP/1.0 on fast path                      | stays off it       |
| remove Router/Acme forms in 0.1.0          | removed (decision) |
| WebSocket block form (codebase item 6)     | already refused    |
|                                            | (:512); no change  |

## Drift report (2026-11-10, after the implementation)

What was built against this draft, item by item. AGENTS.md, LEARN.md,
README.md and UPSTREAM.md name neither form: no drift there.
doc/MESSAGES.md is updated to the one entry point.

As drafted:

* `Server.answer`'s options, the fast-path choice, its timeouts and
  its HTTP/2 preface check; `serve_h1`/`serve_h2` on Incoming and
  Outgoing; `Server.serve`, `Request` and the server's `Response` forms
  removed.
* `Incoming` (version, remote_address, tls_resumed?,
  peer_certificates, body_io) moved into http.iyi; `Outgoing` with
  stream, send, length=, upgrade, close, header(name) and the 6-slot
  state; the refusals (old `call`, `upgrade` without `take_over`, a
  second end) and the "not a server's" raise.
* Compression, SSE.stream(res), WebSocket.upgrade(req, res),
  WebSocket.serve(socket, leftover, res), Router, AcmeHttp01 and
  AutocertView `answer(req, res) : Bool`.

Differs:

* `H2Out` holds the `H2Connection`, not the `Conn`: the server never
  set `conn.h2`, so a streamed HTTP/2 answer raised "the connection
  speaks no HTTP/2" (found by answer_tls).
* `Incoming` has no `form`, `multipart` or `cookies`, which `Request`
  had: a def answering a `Params`, `Multipart` or `Hash` made in its
  scratch is refused (SPEC 1.9), and so are `HTTP.cookie_pairs` and
  `Cookie.parse_header` today. A handler writes
  `Multipart.new(req.body_io, boundary)` itself.
* `Server.parse_request` went with `Request`; std_http_exercise's and
  std_fuzz's parse checks still call it.
* Gates: answer_tls drives TLS with `TlsClient` and HTTP/2 with raw
  frames over cleartext (prior knowledge), as std/http's HTTPS client
  is refused today (`records_handshake` returns an owner). HTTP/2 over
  TLS by ALPN and a 413 on a stream are not gated; they share
  `serve_h2` with h2c. answer_upgrade has no Router: `Pattern.parse`
  is refused by the tape checks (it was before this work); the router
  port compiles only as far as that. answer_compress checks zstd by
  its frame magic: `Zstd.decompress` is refused by the view check.
* The port set's benches did not build before (client owners, views,
  `HTTP.upgrade`, `TlsServerConfig.from_pem`); each now stops first at
  such an error, none at a server form. samples/iyi/autocert.iyi
  stops at `records_handshake`.
