# An idle keep-alive connection yields to a new one

Draft, 2026-11-15, revised after EGM review
(consolidated_review_report.md). Touches SPEC 5.6 (the HTTP server
sentence), src/std/http.ri's serving loops and src/std/socket.ri.

## Problem

`Server.answer` runs N serving tasks (`max_connections`, default 1024
on Linux, 1 on macOS). Each opens its own SO_REUSEPORT listener and
serves one connection at a time, all its keep-alive requests included
(SPEC 5.6). Linux picks the listener for a new connection by a hash of
its addresses and ports, blind to whether that task is busy. A new
connection that lands on a task holding a keep-alive connection waits
in that listener's queue until the held one ends: by the client's
close, or by the head deadline (the sooner of *timeout_ms* and
*request_timeout_ms*).

A TLS client handshakes on connect, so its handshake waits as well and
its own handshake limit runs out first: the error is "took past the
time given to the handshake". Real clients that keep one connection
idle and open a second, or two clients whose hashes meet, see the same
stall. On macOS (N = 1) every second client waits until the first
connection's head deadline ends it.

## Measured, and what is a hypothesis

On minitest (the 32-core build server), about 40 of 400 stressed runs
of test/cli/std_http_stop.ri (`max_connections: 64`, several clients
each holding a connection) failed with the handshake timeout.

Hypothesis, not yet measured: each failure is a new connection hashed
to a listener whose task holds an idle keep-alive. Before coding, one
failing run is logged with the task and listener of each connection to
confirm it. After coding the 400-run stress is rerun as a measurement
(not a gate), counting handshake timeouts; the hypothesis predicts 0.

## Current state in the code

* `Conn#fill` makes one blocking read, of the socket or of the
  `TlsStream`. Every server-side fill puts the connection in
  `IdleConns`, a list `close_for_stop` closes when `serve` stops: mid
  request reads included. `held` (the upgrade's block) uses the same
  list. So `IdleConns` membership is "may be closed at stop", not
  "between requests", and this proposal does not reuse it.
* The waits for a next request's head are in `tape_connection` (the
  fast path in the clear), in `serve_connection`'s HTTP/1.1 loop, and
  in `serve_h2`'s loop between `serve_h2_request` calls.
* There is no wait on two descriptors; `IyiSocket` waits on one
  (`await_readable`, `wait_readable(fd, ms)`).

## The rule

A serving task that waits for the head of a next request on a
connection that is *between requests* also watches its listener. When
a connection is queued there that has sent data, the task ends the
between-requests connection with the server's own close and accepts
the new one. One connection at a time stays the rule; N still bounds
connections served at once.

### Between requests

A connection is between requests when all hold:

* it has been answered at least once: a fresh connection, one in its
  TLS handshake or one before its first request is never ended so;
* HTTP/1.1: the previous answer is written whole, the Conn buffer
  (bytes read, not yet parsed) is empty, and over TLS the `TlsStream`
  holds no decrypted or partial record (`TlsStream#pending?`, new);
* HTTP/2: no stream is open (serving is one stream at a time, so this
  is the wait before the next HEADERS frame), and no frame is buffered
  unparsed;
* it is not handed over (`take_over`, the `held` block) and no handler
  call, body read or answer write is under way.

A TLS record that carries no application data (a session ticket, a key
update) and HTTP/2 control frames (PING, SETTINGS, WINDOW_UPDATE) are
handled as now and leave the connection between requests.

The state is an explicit flag, `Conn#awaiting_head`, set by the three
loops above just before the head wait and cleared when it ends.

### The wait

A new `IyiSocket.await_either(a, b, ms) : Int32 | Cancelled` waits on
two descriptors on the task's poller (epoll on Linux, kqueue on macOS,
which 5.6 allows: "OS facilities on the poller" in one task). It
returns the ready descriptor, 0 at the deadline. It is used only for
the head wait under `awaiting_head`; every other read stays one read.
The head deadline and cancellation work as for a read: cancellation
returns Cancelled and the stop path (`close_for_stop`) is unchanged.

Priority: if the connection is readable, it wins; the listener waits
this round. Only a readable listener with a quiet connection yields.

### Only to a peer that sent data

A bare `connect()` (a health check, a port scan, a browser's spare
connection) must not end a client's connection. The task accepts the
new socket and waits up to
`YIELD_FIRST_BYTE_MS` (100 ms) for its first byte; if none comes, the
new socket is closed and the old connection served on. Two clients
that each send can still take turns: each turn ends with a full answer,
so no request is lost, only a TLS handshake is paid per turn.

### The close

Just before it ends the connection, the task checks once more without
waiting: the Conn buffer, `TlsStream#pending?` and a non-blocking peek
of the socket. Any byte found makes the connection busy: it is served,
and the new connection waits for the next round.

Otherwise the close is today's `Conn#close` unchanged: HTTP/2 writes
GOAWAY first, naming `@highest` (the highest stream id received; all of
them answered when between requests), over TLS `stream.close` sends
close_notify and drains as now, in the clear the lingering close runs
(`LINGER_MS`, `LINGER_BYTES`). No new constant: a client that sent
nothing answers the shut half at once with its own end, so the linger
is short in practice.

What remains: a request sent after the last check and before the shut
is not served. RFC 9112 §9.3 allows a server to close an idle
persistent connection at any time, and §9.3.1 lets a client retry it
only if it is idempotent: a POST that crosses the close is lost to the
client, as it is today when the head deadline ends a connection. Over
HTTP/2 a HEADERS frame past the GOAWAY's id is refused and retryable
(RFC 9113 §6.8).

## SPEC text to change

Current 5.6, its HTTP sentences:

> An HTTP server uses N tasks, each opening its own SO_REUSEPORT
> listener on the same port and accepting and serving one connection at
> a time; N limits connections, with no permits or semaphore. On macOS
> N is 1: it gives a SO_REUSEPORT port's connections to one listener;
> more is refused.

Proposed:

> An HTTP server uses N tasks, each opening its own SO_REUSEPORT
> listener on the same port and accepting and serving one connection at
> a time; N limits connections, with no permits or semaphore. A task
> waiting for a next request's head, with nothing of it buffered and
> every earlier request answered, ends that connection when its
> listener holds a new one that has sent data, and accepts the new one;
> it ends it as the server ends any (GOAWAY over HTTP/2, close_notify
> over TLS, a lingering close). A request that crosses that close is
> not served (RFC 9112 §9.3). Any other connection is never ended so.
> On macOS N is 1: it gives a SO_REUSEPORT port's connections to one
> listener; more is refused.

7.1 (macOS a supported target) is unchanged. Doc comments rewritten to
the rule: `answer`'s *max_connections* (now "A busy worker keeps its
own queue waiting ... including all keep-alive requests"; becomes: a
task in a request or an upgrade still holds its queue back, one
between requests yields), the module header's serving-task line, and
`IdleConns`'s comment (what it is, and that it is not this state).

## Test

New test/cli/std_http_idle_yield.ri, listed in check.sh. One task
(`max_connections: 1`) has one listener, so no hash decides anything:
the test is deterministic. *timeout_ms* is 30 s, far from the 2 s
bound. A and B are raw `IyiSocket` clients (TLS: std/tls clients); the
h2 client is std/http's.

1. Clear and TLS: A sends a GET, reads the answer whole, sends
   nothing. B connects and sends a GET. B is answered within 2 s. A's
   next read returns 0 (end of stream; over TLS close_notify, then 0),
   never ECONNRESET.
2. HTTP/2: A completes stream 1 and waits. B connects. B is answered
   within 2 s; A reads GOAWAY with last stream id 1, then the end.
3. Busy, a partial head: A sends half a request line. B connects and
   sends. A then completes its request: A is answered first, then B
   once A goes between requests.
4. Busy, an HTTP/2 stream open: A's handler waits on a board message
   the test posts after B connects; A is answered, then B.
5. Busy, upgraded: the WebSocket upgrade handler of std_http_stop.ri
   holds A; B connects. B is served after A's upgrade ends (the test
   ends it).
6. Connect only: B connects and sends nothing for 1 s. A's next
   request is still answered on A's connection.
7. Stop: the group is cancelled while the task waits on both; `serve`
   returns and A is closed as by `close_for_stop`.

macOS CI runs it too (N is 1 there, which is the case tested); step 6
on macOS covers `YIELD_FIRST_BYTE_MS`.

## Out of scope

* Ending an idle connection for any other reason (an idle count, a
  shorter idle timeout).
* Moving a queued connection to another task: sockets never cross tasks
  (5.6).
* A connection in a request or upgraded: its new neighbour still waits;
  a larger N is the remedy.
* std's HTTP clients (the other side): their retry rules are unchanged.

## Open questions

* macOS's first-byte wait: 100 ms, or accept the churn of a bare
  connect on macOS (N = 1, a development target) and skip the wait?
* Is a minimum age between requests (e.g. 50 ms) before yielding worth
  it against two clients taking turns? Proposed: no, until measured.
