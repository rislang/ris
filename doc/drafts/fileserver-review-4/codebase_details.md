# Codebase details review (fourth draft)

Verdict: not ready (two Majors). The rest of the citations hold.

Held: log.iyi:400-402 (copy_to(@owner)), :23, :112, :1041, :1045;
region.iyi:523-529; time.iyi `fail` 2774-2781, `finish` 3529-3532,
3635-3639, 3281-3286, 3056; seven Parser `parse` defs (2457, 2463,
3635, 3656, 3671, 3689, 3704; 3736 rightly out); TODO.md:38, :220;
check.sh:64 and its needle; tape.iyi, http.iyi, http_head, io,
file, mime, router, dir and fileserver citations.

## Major

MA-1. Lines 455-463, 627-629: reservations undercounted. Every tape
Array also takes a 128 MiB side reservation (tape.iyi:1163-1166;
side_capacity, region.iyi:532-535). Today an Outgoing holds three
(`@state`, `@lines`, body), the new one five (`@state`, `@spans`,
`@given`, `@text`, body); plus `format_head`'s builder
(http.iyi:2422) and the request's `fields` (2366, 2395). About 7 x
128 MiB per answer, not 2; today about 5, not 1. Count from code;
consider folding `@given` into `@state`.

MA-2. Lines 450-453, 579-580: the `Int32::MAX` clamp is not the
ceiling. A default-capacity builder gets a fixed 128 MiB reservation
on Linux and Darwin (region.iyi:367-370); past it `tape_resize`
raises "tape side reservation exhausted" (region.iyi:487-490). A
*max* over about 128 MiB gives a size error, not a 500, contrary to
"pass a larger *max*". Clamp to SIDE_RESERVE less 40 bytes, or make
the body builder with capacity *want*; probe a 200 MiB *max*.

## Nits

1. Lines 361-365: `refuse` exists (time.iyi:2785-2787), returns
   `TimeParseError`, used at 15 sites in `finish` (3535-3619). Say
   what it returns after the change; recheck "about 40 lines".
2. Lines 310-313, 455: fixed reservations are Linux and macOS
   (region.iyi:367, 487), not Linux only.
3. Line 519: `seek(Int64)` is file.iyi:2150; 2141 unconfirmed.
4. Lines 205-206: `expect` (check.sh:43-52) greps one file, so one
   file goes green once any form is refused; reason misstated.
