# Comprehension review (egm-comprehension)

## What this proposes
Replace `FileServer.serve(root, req) : Response` with
`FileServer.serve(root, req : Incoming, res : Outgoing) : Nil`, writing
status, headers and body into the `Outgoing` that `Server.answer` hands a
handler. HTTP behaviour stays. The body is no longer streamed: the file
or range is read into a pre-sized `res.body`, so peak memory equals file
size per request in flight. Streaming, HEAD length, size cap and Router
are open questions. A new ris test in check.sh guards the compile error.

## How the existing system works, per this document
`serve` builds a `Response` class (header Hash, strings, File) on its own
scratch; SPEC 1.9 lets only a String or flat Array move to the caller, so
callers fail to compile. No ris test calls it. ris-website serves files
itself. `Outgoing` holds up to 32 header lines and a body on the
request's tape, freed after the answer; the server writes Content-Length
from the body and sends no body for HEAD.

## Findings (no Blockers)
Major:
1. "tape"/"scratch" never defined or linked.
2. ris vs iyi and "gate" not explained.
3. SPEC 1.9 not linked; why a class cannot be copied out unexplained.
4. AGENTS.md quotes without path; "answer on the caller's tape"
   fragmentary.
5. `answered_on_tape?` named without saying what it does.
Nit:
6. How Incoming/Outgoing reach a handler.
7. "views or texts" undefined.
8. Where `read_str(count, into)` lives.
9. State plainly: HEAD on 100 MB file loads 100 MB.
10. Symlinks out of root: covered?
11. Router on old Request API loses FileServer: state it.
