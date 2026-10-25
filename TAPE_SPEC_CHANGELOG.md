# TAPE_SPEC.md changelog

Every change to TAPE_SPEC.md gets an entry here in the same commit: date,
what changed and why. Newest first. An agent never edits the spec without
one.

## 2026-10-25: copy_to matches the code

* Was: copy_to deeply copies, keeps aliases and rebases internal links.
  Now: build on the destination where an API can (writers, in-place
  append), else copy_to copies Str bytes and Ary/Tre/@[OnTape] fields
  deep; no aliases kept; pointers, classes, self-relative links refused.
* Why: the old text promised more than src/iyi/tape.iyi does (no identity
  map, no link rebasing). Goose builds at the destination and copies only
  explicitly (§4.1-4.3); self-relative links cannot be copied (§3.9).
  Refusing classes and self-relative links is open work in TODO.md.

## 2026-10-25: failure and exit rules, spec replaces tape docs

* Added: raise unwinding with ensure LIFO and region release; panic data
  copied to the receiver; exhaustion checked before mutation with an
  allocation-free fatal message; exit, fatal errors and signal handlers;
  recursion per Goose §7.8; pending result regions outside callee
  rollback (§10.3); refusal of runtime-sized growing collections;
  closures, bounded queues, thread-locals and FFI callbacks; tooling.
* Changed: Goose citations are informative; to_heap is a migration path
  and copy_to the suggested repair; root structs labelled as planned.
* Why: a review with Codex against Goose and iyi found the spec silent on
  what happens when execution fails or stops, and on where closures,
  queues and task records live without a heap. Without those rules a
  no-GC runtime cannot be built correctly.
