# Drift report: http-idle-yield

2026-11-15. The implementation against http-idle-yield.md, and the docs
CONTRIBUTING.md names (AGENTS.md, LEARN.md, README.md, UPSTREAM.md)
against the new SPEC 5.6 text. Written by hand: the EGM drift skill was
not available to the worker.

## The measurement (draft: "Measured, and what is a hypothesis")

Confirmed before coding. One failing run on minitest (run 25 of a
sequential loop) logged each accept and end per listener and took
`ss -ltnpe` 5 s into the stall:

    L15 accept 46780     (the TLS client kept alive, HTTP/1.1)
    L18 accept 46782     (the TLS client kept alive, HTTP/2)
    client: waiting connects
    panic: tls: localhost took past the time given to the handshake
    L18 end 46782, L15 end 46780   (at the head deadline, 10 s on)

    ss: 64 listeners on the TLS port; Recv-Q 1 on fd 15, 0 on the 63
    others.

The new connection sat in the queue of the one listener whose task held
the idle keep-alive connection, while 63 tasks waited in `accept`.

## Code against the draft

* The rule, between requests: as drafted. `Conn#awaiting_head` is set
  by `tape_connection`, `h1_request` (via `serve_h1`) and
  `H2Connection#next_request` only after a first answer, and cleared
  when the wait ends. HTTP/2 also needs no open stream and no header
  block in progress (`@block_stream == 0 && @streams.empty?`), checked
  before each frame read, so a PING or SETTINGS read meanwhile leaves the
  connection between requests. `Conn#fill` yields only with its buffer
  empty and, over TLS, `TlsStream#pending?` false.
* The wait: drafted as `IyiSocket.await_either(a, b, ms)`. Built as
  `await_either(poll, a, b, ms)`: *poll* is an epoll (Linux) or kqueue
  (darwin) instance the serving task opens once (`IyiSocket.watcher`),
  its listener an interest for the task's life and each connection's
  socket added at its first between-requests wait (`watch`); the task
  parks on it through the scheduler like on any descriptor. One instance
  per task, not one per wait, keeps the keep-alive fast path at one
  extra `poll(2)` per wait. Other targets get no watcher and keep
  today's single read.
* Priority: as drafted, the connection is checked first each round.
* Only to a peer that sent data: Linux sets TCP_DEFER_ACCEPT (30 s,
  `IyiSocket::DEFER_ACCEPT_S`) on the serving listeners. macOS accepts,
  waits `Conn::YIELD_FIRST_BYTE_MS` (100 ms) and, with a byte, hands the
  socket to the serving loop through `IdleConns` (`release_fd`,
  `adopt`); otherwise closes it and serves on.
* The close: the last look (buffer, `pending?`, a `poll(2)` of the
  socket) as drafted; then today's `Conn#close` (GOAWAY over HTTP/2,
  close_notify over TLS, a lingering close in the clear). `tape_connection`
  used to close at once on a failed head read; a yield now closes by
  lingering there, and `h1_request` reports it as "this side wrote last".
* Stop: unchanged. A cancellation during the wait returns Cancelled, kept
  as the connection's failure, as a cancelled read was.

## Not as drafted, or left open

* A client that connects and then closes without sending: its FIN ends
  TCP_DEFER_ACCEPT's wait, so the listener turns readable and an idle
  connection yields to a connection that has already ended. Rare, and
  the cost is one TLS handshake for the yielded client; not tested.
* After DEFER_ACCEPT_S a bare connect is queued anyway and may take an
  idle connection's place; it is then served until the head deadline,
  as today.

## Test (draft: "Test")

test/cli/std_http_idle_yield.ri has the seven steps, in check.sh's list
of run-time tests (so macOS CI runs it too: N is 1 there, the case
tested; step 6 covers the 100 ms first-byte wait). With the yield turned
off it fails steps 1 to 4 (B waits; the TLS handshake times out).
HTTP/2 is framed by hand on a raw socket so that GOAWAY's last stream id
can be read; step 4's open stream is the board-waiting handler.

## Documents

* SPEC.md 5.6: the drafted sentence, word for word. 7.1 unchanged.
* AGENTS.md, LEARN.md: nothing on HTTP serving; no drift.
* README.md: "an HTTP server there takes one connection at a time" (macOS)
  is still true; no change.
* UPSTREAM.md: new entry for the std/socket and std/tls pieces, which
  need no tape.
* src/std/http.ri: the module header, `answer`'s *max_connections* and
  `IdleConns`'s comment rewritten as the draft asked.
