# EGM Review Report: http-idle-yield

**Target:** `doc/drafts/http-idle-yield/http-idle-yield.md` (whole draft)
**Code checked:** `src/std/http.ri`, `src/ris/concurrency.ri`,
`src/std/socket.ri`, `src/std/tls.ri`, SPEC.md 5.6,
`test/cli/std_http_stop.ri`

## Reviewer Status

| Reviewer | Status |
| --- | --- |
| `codebase-details` | completed |
| `design` | completed |
| `implementation-readiness` | completed |
| `zoom-out` | completed |
| `comprehension` | completed |
| `inventive-catalyst` | completed |
| `style`, `structural` | not run (optional) |

Verdict: the rule is the right direction (zoom-out found no simpler
design that still fixes the stall), but it is not ready to implement:
3 Blockers, 6 Majors.

## Blockers

### B1. No two-descriptor wait exists; the draft does not design one
* **Lens:** codebase-details, design, impl-readiness, inventive
* **Scope:** "Watching" (lines 70-73)
* **Problem:** `Conn#fill` (http.ri:552-593) makes one blocking
  `socket.read`/`stream.read`. The single-fd waits are
  `wait_readable(fd[, ms])` (concurrency.ri:3759-3769) and
  `await_readable` (socket.ri:1333, 1559-1573). Nothing waits on a
  connection and a listener together. For TLS the wait is inside
  `TlsStream#read`.
* **Fix:** name the primitive and its owner, e.g.
  `wait_readable_either(a, b, ms) : Int32 | Cancelled` (returns the
  ready fd, 0 on timeout). Check whether socket.ri:931
  (`wait_readable(poll, ms)`) can be reused. Say how it works with the
  epoll and kqueue pollers, with `deadline`/`gap`, and with
  cancellation. Use it only for the head wait; every other read stays
  a plain read.

### B2. "Idle" over TLS ignores bytes buffered in TlsStream
* **Lens:** design, impl-readiness, inventive
* **Scope:** "Idle" bullets (lines 41-45)
* **Problem:** when the Conn buffer is empty and the socket is not
  readable, `TlsStream` may still hold decrypted plaintext or part of
  a record, so the yield drops a request already sent. In the other
  direction, a readable socket may carry only a NewSessionTicket,
  KeyUpdate or alert.
* **Fix:** a connection is idle only when all three hold: the Conn
  buffer is empty, `TlsStream#pending?` (new) is false, and a
  non-blocking peek of the socket finds nothing. Say a non-application
  record does not make the connection busy. Add a negative test where
  the next request arrives in the same segment as the previous record.

### B3. The draft's "idle" clashes with the existing IdleConns, and the
call sites are not named
* **Lens:** codebase-details, design, impl-readiness, zoom-out
* **Scope:** line 4 ("Touches"), lines 41-52, 70-73
* **Problem:** every server-side `Conn#fill` already registers in
  `IdleConns` (http.ri:213-274, 570-577), mid-request reads included,
  and `held` (http.ri:769-782) uses the same list. `Server.answer`
  only validates and calls `prefork` (http.ri:2436-2456). The real
  waits are in `tape_connection` (http.ri:2484, 2493), which carries
  the fast path for plain traffic (http.ri:2847-2849), and in
  `serve_connection`/`h1_request` (from http.ri:2903), `serve_h2`
  (http.ri:2471) and `fill`. `fill` cannot tell a head wait from a
  body or frame read.
* **Fix:** add a "Current state" paragraph on `IdleConns`, `fill`,
  `held` and `handed_over`. Rename the draft's state (e.g.
  `awaiting_head`) and make it an explicit flag set by the caller at
  http.ri:2484 and in the h1 and h2 loops; do not use IdleConns
  membership. List every function touched, how a yield is reported
  back (e.g. `Conn#yielded`), and how `run_worker` returns to
  `accept` (http.ri:2836-2857).

## Majors

### M1. The close procedure contradicts itself and is wrong for TLS
* **Lens:** all six
* **Scope:** lines 54-68, proposed SPEC text (96-98)
* **Problem:** line 57 says the yield uses today's `Conn#close` with
  `LINGER_MS`/`LINGER_BYTES` (http.ri:840-859). Lines 63-68 add
  `YIELD_LINGER_MS` = 100 ms. Over TLS, `Conn#close` calls
  `stream.close` (http.ri:805-806), which drains under tls.ri's
  `DRAIN_GAP_MS` (tls.ri:1768-1782) and never uses `linger`.
* **Fix:** pick one close. Recommended (zoom-out and inventive agree):
  no new constant. Peek just before the yield; if a byte is waiting
  the connection is busy and is served. Otherwise `shutdown(WR)`,
  check FIONREAD or do one non-blocking read, then close at once. If
  a shortened linger is kept, define `Conn#close_for_yield` with the
  order GOAWAY / close_notify / close_write / drain / close. Cover the
  TLS drain as well, state whether `LINGER_BYTES` caps the drain, and
  make the SPEC wording match.

### M2. Race between the poll and the shutdown; non-idempotent loss
* **Lens:** design, comprehension, inventive
* **Scope:** lines 57-61
* **Problem:** RFC 9112 §9.3.1 lets clients retry only idempotent
  requests. A POST that crosses the shutdown is lost. Today this
  happens once per timeout; with the rule it can happen on every
  arriving connection. The draft also does not say which wins when
  both descriptors are ready at once.
* **Fix:** state the priority: a readable connection is busy and the
  listener waits this round. Make the peek from B2 the last step
  before `shutdown`. Name the remaining race in the draft and in the
  SPEC sentence. Optionally, if bytes arrive during the drain, abort
  the yield and serve them.

### M3. Fresh connections and connect-only peers cause eviction churn
* **Lens:** design, inventive, zoom-out
* **Scope:** "Idle" definition; "Watching"
* **Problem:** the listener becomes readable once the TCP handshake
  completes. Health checks, port scanners or a single `connect()`
  evict idle clients; on macOS (N=1) one prober is enough. The state
  of a connection that is accepted but has sent no request yet is
  undefined. Two clients (or a browser's 6 connections) can evict
  each other in turn, paying a TLS handshake each time.
* **Fix:** a connection is not idle before its first request and
  never during its handshake (say so explicitly). Yield only to a
  peer that has sent data: `TCP_DEFER_ACCEPT` on Linux; on macOS,
  accept the new socket and wait briefly for its first byte. Consider
  a short minimum idle age, described as a guard against thrashing.

### M4. HTTP/2 idle and GOAWAY are not defined in code terms
* **Lens:** codebase-details, impl-readiness, inventive
* **Scope:** lines 47-49, 55
* **Problem:** `goaway` writes `@highest` (http.ri:7749-7752), the
  highest stream id received, not "the last answered". The draft
  names no predicate for "no open stream", does not say whether
  buffered but unprocessed frames count as busy, and does not say
  what happens to a HEADERS frame that crosses the GOAWAY.
* **Fix:** name the predicate (e.g. `open_streams == 0` and an empty
  frame buffer). Say "highest id received; all answered when idle".
  Cite RFC 9113 §6.8 for the refused, retryable stream, and test it.

### M5. The cause and the result are asserted, not measured
* **Lens:** design, codebase-details, comprehension
* **Scope:** lines 24-29, 67-68, 128
* **Problem:** "fits the hash collision", "no run failed for another
  reason" and "expected 0 failures" have no data behind them.
* **Fix:** log the listener and task per connection in one failing
  run, or label these as hypotheses that the stress rerun will test.
  Say that the stress run counts handshake timeouts only.

### M6. Test steps lack observable expectations
* **Lens:** impl-readiness, comprehension, design, inventive
* **Scope:** "Test" (lines 109-128)
* **Problem:** step 4 does not name client A or what it reads.
  Step 6 ("not answered within 2 s") proves little, has no end
  condition and costs 2 s per case. The upgraded case names no
  handler. No h2 client is named. There are no cases for an open h2
  stream (busy) or for a stop during the new wait.
* **Fix:** A is a raw `IyiSocket`; `read` returns 0, not ECONNRESET.
  In step 6, assert B is answered once A finishes or goes idle, and
  use a short *timeout_ms* (e.g. 5 s). Name the `take_over` handler
  (or fold this into an existing upgrade test). Add: an h2 stream is
  open (busy); a group is cancelled during the two-fd wait and still
  reaches `close_for_stop`. Say how check.sh registers the test and
  whether macOS CI runs it (recent commits skip two-connection tests
  there).

## Minors

* **m1. Handshake timeout figure (line ~15).** The server uses
  *timeout_ms* or `HANDSHAKE_TIMEOUT_MS` (http.ri:2886); the test
  client waits 10 s (std_http_stop.ri:349). Say whose 30 s is meant.
  Fix: replace "60 s of idleness" with "the head deadline" (min of
  *timeout_ms* and *request_timeout_ms*, http.ri:2483, 2896-2901).
* **m2. Doc comments.** List all three: `answer` (http.ri:2416-2418),
  http.ri:33 and the `IdleConns` comment (213-216). Quote the new
  *max_connections* text, including that a busy or upgraded task
  still holds its queue back.
* **m3. SPEC sentence.** It omits the handshake case. Fix: define idle
  positively ("waiting for a next request's head with nothing
  buffered") instead of listing exceptions.
* **m4. Undefined terms.** "board", "Conn buffer", "head wait",
  "`held` block", `take_over`, "minitest", `check.sh`: gloss each one
  or link to its definition.
* **m5. macOS paragraph (lines 75-77).** Rewrite as "a second client
  waits until the first connection's idle timeout ends it".
* **m6. HTTP/2 detail level.** Leave PING/SETTINGS handling to the code,
  and add one line on why HTTP/2 is not deferred.
