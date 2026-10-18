# ris tape memory: current design

Architecture: GC + optional tape is decided. The tape implementation is
experimental; this contract is not a proof of complete memory safety.
The inherited [SPEC.md](SPEC.md) describes iyi and is kept unchanged.
An example is in [README.md](README.md).

## Allocation and ownership
Ordinary objects use iyi's collected heap. Tape is opt-in: `TapeString`,
`TapeWriter` and `TapeArray(T)` allocate on the running fiber's tape.
`@[OnTape]` marks a struct as tape-bearing; it does not move the struct
or its fields onto the tape. A tape allocation outside an active
`Tape.scope` or `Tape.local` terminates the program. Each fiber has its
own tape, saved and restored on a switch. Allocation is bump-pointer; the
first mapping is 64 MiB of address space (only written pages are resident,
std/http's `MAX_BODY` fits), and a full tape adds a larger one. Each thread
keeps up to 64 first-size mappings as warm spares, first MiB resident.

Only the outermost `Tape.scope` reclaims, on every exit (panic and exit
too, LIFO with defers); nested scopes share its tape. A scope returns
`Nil`; a non-tape `break` value can leave it. `Tape.local` always takes an
independent tape, even inside a scope, released and the previous restored
on every exit; a `Tape.scope` inside one shares it.

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

Copying a `TapeArray` or `TapeWriter` aliases its state. Growth off the top
copies, leaving the old until scope exit: element references are not
stable. Tape words are GC roots: tape cuts heap allocation, not scanning.

## Layout: write the tape in order
Tape pays when written in order: one growing value at the top, all else
written once, whole. Mixed building (a `TapeArray` per node, filled while
its children are made, as a classic object-tree YAML or JSON parser does)
copies the parent on each growth. 4.6 MB JSON, 20 parses, best of 7:

| layout, `--release`, 2026-10-17 | time | RSS | tape allocations |
|---|---|---|---|
| `TapeArray` per node, pushed while parsing | 1862 ms | 126 MB | 1,320,548 |
| same, children gathered on a stack first | 1452 ms | 93 MB | 1,320,548 |
| Goose: one pool, children first, index links | 842 ms | 59 MB | 2 |

For a tree, use the Goose layout (its `samples/18_json.goose`): nodes in
one pool, children before their parent, siblings linked by index, strings
as views of the input (`TapeArray` has no `[]=` yet to set links). Do not
port mixed building to tape: too little gain to rewrite for. Streaming (one
`TapeWriter`, input views: std/http, Slim) already grows in place.

## Implementation and checks
* `src/iyi/`: `tape.iyi` scopes and containers, `prelude.iyi` mappings
  and GC roots, `concurrency.iyi` fiber switching.
* [TapeChecker](src/compiler/iyi/semantic/tape_checker.cr): storage types;
  [TapeLifetimeChecker](src/compiler/iyi/semantic/tape_lifetime_checker.cr):
  calls, yield bindings, assignments, scope exits.
* `CleanupTransformer#check_tape_captures`: proc captures;
  `test/ris/check.sh`: refused programs, exits, nesting, growth, fibers.

## Interfaces and remaining work
Use `to_s` at a lifetime boundary, not tape/heap variants of each method.
Before calling this stable: audit lifetime checks across all features,
specify pointer/FFI boundaries, measure copy-out, GC scanning, long scopes
and many fibers. A long scope keeps superseded buffers; `Tape.local` bounds
temporary work.
