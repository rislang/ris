# Zoom-out review (egm-zoom-out)

Direction right, fixes the cause, reuses Outgoing. No blockers.

## Major
1. HEAD reads the whole file only to count it: a regression (old code
   read nothing). Settle Q2 now: a length override in Outgoing
   (`res.length = n`, slot in @state), used by format_head; ~5 lines.
2. Memory unbounded; `read_str(count : Int32, into)` cannot read >2 GiB
   in one call. Answer Q3 now: a cap (e.g. 8 MiB, constant or `max`
   param), above it a named status. Name the follow-up: Outgoing file
   body via existing sendfile (src/socket.cr:372); the cap goes then.

## Nit
1. Mapping section too code-detailed.
2. Behaviour list repeats module doc; instead list what changes and
   update the doc comments "read as it is sent, never whole"
   (fileserver.iyi:13-14, 49-50).
3. Router example should say Router cannot serve files until ported.
4. Tests: HEAD Content-Length + no body; file over the cap.
