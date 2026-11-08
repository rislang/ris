# Intermediate zoom out (egm-zoom-out, second pass)

Target: doc/drafts/fileserver-outgoing.md. The change hangs together;
every piece follows from a probed refusal. Phase split is right.

## Major

* Z2-1 (470-475, 491-492): P1b. If inline arguments are sound, B1's
  block form, `@text` and `@spans` work around an over-strict check;
  if it is a hole, `header(name, value)` lets a dangling scratch view
  into `@lines`, and 143-145 and A6 lean on that path. Settle it with a
  probe (serve the inline value after scratch is reused) before
  Phase 1. Blocker if the probe dangles.
* Z2-2 (132-141): `@spans` with a -1 sentinel keeps two forms per line
  in parallel arrays. Decide Z2-1 first; say why `Field` cannot hold a
  span.

## Nit

* `@size` one-slot Array (156): say "as `@state`".
* `length=` (151): consider `head_length=`.
* Private helper list (266-294) is below design altitude.
* Int32 clamp (203-211): one clause is enough.
* IMF parser (255-264): note in the follow-up that it is deleted when
  `HTTP_DATE.parse` compiles.
* Bench removal (357-363): map each bench case to a numbered test.
