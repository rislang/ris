# Style review (egm-style)

No blockers. No line over 80 chars.

## Major
1. L78-80 "it is fast ... not": unmeasured. Say one read, one write, no
   chunking; memory per request equals file size.
2. L87 "cost nothing": overstated; sendfile still does I/O. Say HEAD
   reads no file, large files use no tape memory.
3. L47-48: clause after the AGENTS.md quote dangles. Split.
4. L10: too many nested clauses.

## Nit
5. L15-21: 11 behaviours in one sentence; make a list.
6. L55-56 "well under": filler.
7. L67-68 "short text body where the old def gave one": name them.
8. L75-76: split; "peak is the sum of file sizes of requests in flight".
9. L94 "refuse (or 500)": name the status (500/413/507?).
10. L88-90: passive; "This draft leaves it for a later change."
11. L115: optional "(see Problem)".
