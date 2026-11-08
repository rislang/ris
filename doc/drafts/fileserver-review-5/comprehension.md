# Comprehension review, fifth draft

(Saved by the synthesizer; the reviewer had no write tool.)

## Prior round (review 4)

* M1 resolved: counted table (508-516), Risks agrees (691-693),
  `@given` folded into `@state`.
* M2 resolved: clamp at 492, P14, fileserver.iyi:132.
* M3 resolved: P1 form -> gate table (112-118), `n.to_s` fills
  (206-226), five-file reason (230-232), P13.
* M4 resolved: check.sh block (747-776) at check.sh:1197-1203.
* Nits addressed.

## Draft vs code

fileserver.iyi agrees: step order, clamp before cap, HEAD
`res.length = count` (140), bodies, helpers, imports, constants.
check.sh blocks (851, 1197, 1205-1217) and TODO.md:222-234 exist.

## Findings

Blockers: none. Majors: none.

Nits:
1. 391 vs 680: std/time fix "about 50" vs "about 40" lines.
2. 4, 33: "EGM" and "tape ports" undefined.
3. 297: `LINES * 2 (64)` before LINES is defined (486); gloss it.
4. 287-291 vs 510: "a fourth slot" vs "two more slots"; say
   "today [status, count]; adds the block flag and the length".
5. 800 vs 808-809: is the final `Connection: close` GET an extra
   request or case 1? One sentence.
6. 606-607: explain `byte_range`'s `Bool | Nil` (fileserver.iyi:
   120-124).
7. Lines 260 and 811 exceed 80 characters.
8. 725: `check.sh:843-849` is pre-change; say so.

Verdict: ready from the comprehension side.
