# Intermediate zoom-out (fourth draft)

Checked http.iyi:2213-2264, 2415-2461; region.iyi:523-534.

1. Memory (455-461): real Major. Today one growing payload, `@body`
   (http.iyi:2231), about 128 GiB at 1024 answers; `@text`
   (1024 bytes, below SIDE_RESERVE, region.iyi:529) adds a second:
   about 256 GiB, caused by this change. Contradicts Risks 627-629.
   Fix the text and name the strict-overcommit effect. Reject a
   fixed-capacity `@text`: std has no such builder (YAGNI).
2. Stale http.iyi:2214-2216 sentence: real, Nit. Replace it.
3. HEAD bodies: mostly settled by code. The server drops every HEAD
   body (http.iyi:2446, 2458). Nit: say FileServer writes the same
   body on HEAD, so the cap 500's Content-Length is defined (443).
4. Five forms and `_instance`/`_class` gates: real, sized Minor.
   Use `k.put(n.to_s)` there and count one way. Gates land with the
   compiler fix, not this change.
5. outgoing_refusals.sh: real, Minor. Give hook and pass rule, or
   fold into one `.ri` with a PASS line if raises can be rescued.

New Nit: `read_into` listing (489-509) is implementation detail.
No Blockers.
