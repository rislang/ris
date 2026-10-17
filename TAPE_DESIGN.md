# ris tape memory: current design

Architecture: GC + optional tape is decided. The tape implementation is
experimental; this contract is not a proof of complete memory safety.
The inherited [SPEC.md](SPEC.md) describes iyi and is kept unchanged.

## Example
```crystal
@[OnTape]
pub struct Order
  getter id : Int64
  getter customer : TapeString
  getter lines : TapeArray(Int64)
end
Tape.scope do
  order = make_order(1_i64)   # its TapeString/TapeArray storage uses tape
  body = render(order).to_s   # `to_s` copies out what must outlive it
end                           # all tape storage reclaimed together
```

## Allocation and ownership
Ordinary objects use iyi's collected heap. Tape is opt-in: `TapeString`,
`TapeWriter` and `TapeArray(T)` allocate on the running fiber's tape.
`@[OnTape]` marks a struct as tape-bearing; it does not move the struct
or its fields onto the tape. A tape allocation outside an active
`Tape.scope` or `Tape.local` terminates the program. Each fiber has its
own tape, saved and restored on a switch. Allocation is bump-pointer; the
first mapping is 64 MiB, and a full tape adds a larger one without moving
anything. 64 MiB is address space, not memory: only written pages are
resident, a mapping costs the same at any size, a request rarely grows past
it (growth copies the growing value), and it holds the largest request
body std/http accepts (`MAX_BODY`). Reclamation releases the chain; each
thread keeps up to 64 first-size mappings as spares, newest first, so
scopes open at once (handlers that park) reuse warm pages. A spare keeps
its first MiB resident and hands the rest back; grown mappings are
unmapped, and a thread's spares go when it ends.

Only the outermost `Tape.scope` reclaims; nested scopes share its tape.
Its guard reuses one cleanup node per fiber: normal and nonlocal exits
release directly, panic and exit drain it in LIFO order with defers. A
scope returns `Nil`; a non-tape `break` value can leave it.

`Tape.local` always takes an independent tape, even inside another scope,
and releases it and restores the previous tape on every exit, through an
ordinary (heap-allocated) defer guard. Released mappings share the spare
cache. Locals nest; a `Tape.scope` inside one shares it.

## Lifetime and storage rules
The invariant: no safe tape-bearing value survives reclamation of the
scope or local tape that owns its storage.

* Tape values may be locals, arguments/results within that lifetime,
  fields of `@[OnTape]` structs and elements of `TapeArray(T)`; not fields
  of classes or ordinary structs, class variables or type arguments of
  ordinary containers such as `Array(TapeString)`.
* No proc, spawned block included, may capture a tape-bearing value.
* Assignment, `return` and `break` must not carry one past its owning
  scope, wrapped in unions or tuples included. Synchronous `yield` is
  allowed under the same rules. Nested scopes share one lifetime.
* `Tape.local` starts a new lifetime: its values cannot reach outer locals,
  returns or yield bindings. It may read outer `TapeString`s; other outer
  tape values, `self` included, are converted to owned data first, since
  distinct region lifetimes are not tracked in types.
* `TapeString#to_s : String` copies into GC storage. Raw pointers and
  internal allocator calls are outside the contract.

Copying a `TapeArray` or `TapeWriter` aliases its state. Growth may copy to
a new allocation, leaving the old until scope exit; unlike Goose, element
references are not stable on growth. Tape words are scanned as GC roots:
tape reduces heap allocation, not GC or its scanning.

## Implementation and checks
* `src/iyi/`: `tape.iyi` scopes and containers, `prelude.iyi` mappings
  and GC roots, `concurrency.iyi` fiber switching.
* [TapeChecker](src/compiler/iyi/semantic/tape_checker.cr): storage types;
  [TapeLifetimeChecker](src/compiler/iyi/semantic/tape_lifetime_checker.cr):
  calls, yield bindings, assignments, scope exits.
* `CleanupTransformer#check_tape_captures`: proc captures;
  `test/ris/check.sh`: refused programs, exits, nesting, growth, fibers.

## Interfaces and remaining work
Prefer tape for bounded work; keep borrowed return types explicit and use
`to_s` at a lifetime boundary rather than tape/heap prefixes on every
method. Before calling this stable: audit lifetime checks across all
features, specify pointer/FFI boundaries and limits, and measure real
workloads, copy-out, GC scanning, long scopes and many fibers. A long
scope keeps superseded buffers; `Tape.local` bounds temporary work.
