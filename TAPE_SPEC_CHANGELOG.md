# TAPE_SPEC.md changelog

Every change to TAPE_SPEC.md gets an entry here in the same commit: date,
what changed and why. Newest first. An agent never edits the spec without
one.

## 2026-10-25: aliasing, sharing, messages, exit, byte images

* Added: Ary, Tre and builders are handles; assignment and arguments
  alias, only copy_to copies; Str is read-only. The spec is the target
  contract, gaps are in TODO.md. Byte images are checked field by field
  and never published in part. Runs with self-relative links never move.
* Changed: sharing is iyi's Share, "frozen" is gone; channels carry only
  Share values until TODO 7. exit runs the calling task's defers, as
  iyi III.1.4; only fatal errors skip cleanup.
* Why: a Codex review found assignment, writability, queued message
  ownership and byte validation unstated, and ris's exit differed from
  iyi without a tape reason. The code already aliases (Ary and builders
  hold one state pointer); Share already defines read-only data.

## 2026-10-25: reuse iyi's rules instead of restating them

* Changed: errors, panics and defer cite iyi III.1-III.1.4; the fatal
  message is iyi's panic print; signals are std/signal's; init order is
  iyi III.5; data races are iyi's Share (III.4.4); messages use iyi's
  Channel, select, ChannelClosed and Cancelled (III.4). ris states only
  what tape adds: region release, copies to the receiver, full queues.
* Changed: "a fiber may outlive its spawner" is replaced by iyi's group
  rule (III.4.1): a task never outlives its group; long work runs in a
  longer group, such as main's. "main's return ends all fibers" is gone
  with it, since main's group joins its tasks.
* Why: iyi already builds these; two specs saying the same thing drift
  apart, and the fiber rule contradicted iyi. ris reuses iyi where it
  fits and designs only what tape needs.

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
