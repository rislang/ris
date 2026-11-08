# Style review, fifth draft

(Saved by the synthesizer; the reviewer had no write tool.)

Verdict: ready. No Blockers, no Majors. Review 4 M1-M4 resolved.

Nits:
1. 121-122: broken reflow; rewrap.
2. 811 exceeds 80 characters.
3. 391 vs 680: "about 50" vs "about 40" lines.
4. 800-801 vs 807-809: second `Connection: close` request reads
   as extra; fileserver.ri:179 has one.
5. 7-8: drop "the 32-core build server".
6. 98-99: "files it with its gates" vs gates land with the fix
   (134-135, 712-713).
7. 681-683: "the same reason", "a third copy" lack antecedents.
8. 326: `refusal` called private; code is protected
   (http.iyi:2288).
9. 614-616: ETag and date use the block form
   (fileserver.iyi:184-185).
10. 630-632: module doc differs from fileserver.iyi:16-19.
