# ris tape memory: current design

Architecture: GC + optional tape is decided. The tape implementation is
experimental; this contract is not a proof of complete memory safety.
The inherited [SPEC.md](SPEC.md) describes iyi and is kept unchanged.

## Allocation and ownership
Ordinary objects use iyi's collected heap. Tape is opt-in: `TapeString`,
`TapeWriter` and `TapeArray(T)` allocate backing storage on the running
fiber's tape. `@[OnTape]` marks a struct as tape-bearing; the annotation
alone does not move the struct or all of its fields onto the tape.

A tape allocation needs an active `Tape.scope` or `Tape.local`. Tape
allocation outside one terminates the program. Each fiber has its own active tape; switching
fibers saves and restores it. Allocations are bump-pointer allocations.
The initial mapping is 64 MiB; a full tape adds a larger mapping without
moving existing allocations. The scope releases the mapping chain and
retains one mapping as a spare for reuse by that thread.

Only the outermost `Tape.scope` owns reclamation. Nested scopes share its
tape and reclaim nothing on their own. Its internal guard reuses one
cleanup node, allocated once per fiber. Normal exits (including nonlocal
`return`/`break`) detach it and release directly. Panic and exit drain it
in LIFO order with ordinary defers; later scopes need no GC allocation.
A scope normally returns `Nil`; a non-tape `break` value can leave it.

`Tape.local` always acquires an independent tape, even inside another
scope or local tape. Its cleanup releases the entire local mapping chain
and restores the previously active tape on normal exits, nonlocal exits,
panic and exit. It uses an ordinary defer guard (including its heap
allocation), rather than the single cached outer-scope guard. Released
mappings use the same spare cache; repeated calls can reuse warm storage.
Local tapes can nest, and ordinary `Tape.scope` inside one shares it.
Copy retained results with `.to_s` before leaving the local tape.

## Lifetime and storage rules
The intended invariant: no safe tape-bearing value survives reclamation
of the tape scope or local tape that owns its storage.

* Tape values may be locals, method arguments/results within that lifetime,
  fields of other `@[OnTape]` structs, and elements of `TapeArray(T)`.
* They may not be fields of classes or ordinary structs, class variables,
  or type arguments of ordinary containers such as `Array(TapeString)`.
* A proc, including a spawned block, may not capture a tape-bearing value.
* Assignment, `return` and `break` must not carry a tape-bearing value past
  its owning scope. Checks include values wrapped in unions or tuples.
* Synchronous `yield` is allowed. Its block may consume a tape value or
  copy data out, but must obey the same lifetime restrictions.
* Nested scopes may pass tape values back into the still-active outer
  scope: both scopes use the same storage lifetime.
* `Tape.local` starts a new lifetime: its values cannot be assigned to
  outer locals or returned through an enclosing method or yield binding.
  Outer `TapeString` values may be read. Other outer tape values, including
  an outer tape receiver's `self`, must be converted to owned data before
  entering. This conservative restriction prevents indirect mutation of
  outer tape containers; distinct region lifetimes are not tracked in types.
* `TapeString#to_s : String` copies bytes into independent GC-managed
  storage. Numeric results can leave without retaining tape storage.
* Raw pointers and direct internal allocator calls are outside this safe
  contract. A pointer into tape storage becomes invalid at reclamation.

Copying a `TapeArray` or `TapeWriter` aliases its state; it does not create
independent storage. Growing their backing buffers may copy bytes to a
new allocation, leaving the old storage until scope exit. This does not
provide Goose's general guarantee of stable element references on growth.
Tape words are scanned as GC roots, so tape-held heap references stay live.
Tape reduces heap allocation; it does not remove GC or its scanning work.

## Implementation and checks

* [tape.iyi](src/iyi/tape.iyi): the public scope and tape containers.
* [prelude.iyi](src/iyi/prelude.iyi): `IyiRegion`, mappings and GC roots.
* [concurrency.iyi](src/iyi/concurrency.iyi): fiber tape switching.
* [TapeChecker](src/compiler/iyi/semantic/tape_checker.cr): storage types.
* [TapeLifetimeChecker](src/compiler/iyi/semantic/tape_lifetime_checker.cr):
  calls, lexical yield bindings, assignments and scope exits.
* `CleanupTransformer#check_tape_captures`: proc capture restrictions.
* `bash test/ris/check.sh`: accepted/refused programs, early exits, nested
  scopes, zero-capacity growth, fiber isolation and mapping growth.

## Readable interfaces and remaining work

Prefer tape for bounded work. Keep borrowed return types explicit in method
signatures; retained destinations accept String. Use `to_s` at a lifetime
boundary instead of adding tape/heap prefixes to every domain method. This
does not infer allocation or remove the need for an active scope. Ordinary
objects still use GC storage; only tape-backed types allocate on the tape.

Before treating this model as stable, audit lifetime checks across all
language features and specify pointer/FFI boundaries and resource limits.
Measure real workloads, copy-out costs, GC scanning, long-lived scopes and
many fibers. A long outer scope retains temporary and superseded buffers;
use `Tape.local` to bound temporary copy-out work within that scope. A
favorable request-loop benchmark alone does not establish general gains.
