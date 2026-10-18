# ris tape memory: current design

Architecture: GC + optional tape is decided; the tape is experimental, and
this is no proof of memory safety. [SPEC.md](SPEC.md) describes iyi,
unchanged; an example is in [README.md](README.md).

## Allocation and ownership
Objects use iyi's GC heap. Tape is opt-in: `TapeString`, `TapeWriter`,
`TapeArray(T)` allocate on the running fiber's tape (saved on a switch);
`@[OnTape]` marks a struct tape-bearing without moving it. Tape allocation
outside `Tape.scope` or `Tape.local` ends the program. Bump-pointer; the
first mapping is 64 MiB of address space (written pages resident, fits
`MAX_BODY`), a full tape adds a larger one; each thread keeps 64 spares.

Only the outermost `Tape.scope` reclaims, on every exit (panic too, LIFO
with defers); nested scopes share it. It returns `Nil`; a non-tape `break`
value can leave. `Tape.local` always takes its own tape, released on every
exit; a `Tape.scope` inside one shares it.

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
* `Tape.local` starts a new lifetime: its values reach no outer locals,
  returns or yield bindings. It may read outer `TapeString`s; other outer
  tape values, `self` too, become owned data first (lifetimes are untyped).
* `TapeString#to_s : String` copies into GC storage. Raw pointers and
  internal allocator calls are outside the contract.

Copying a `TapeArray` or `TapeWriter` aliases its state. Growth off the top
copies, leaving the old until scope exit: element references are not
stable. Tape words are GC roots: tape cuts heap allocation, not scanning.

## Layout: write the tape in order
Tape pays when written in order: one growing value at the top, all else
written once. Streaming pays most: `samples/ris/respond.ri`, 1.6M DTOs as
JSON, one `TapeWriter` per response; each tool's release build, median of 9:

| respond, DTO (2026-10-18) | memory | time | RSS |
|---|---|---|---|
| Goose: default, `cc -O2` | own data stacks | 0.68 s | 2.0 MB |
| ris: `--release` | tape | 0.70 s | 1.7 MB |
| C++: `g++ -O3 -DNDEBUG` | malloc per string/list | 0.99 s | 4.1 MB |
| C: `gcc -O3 -DNDEBUG` | malloc per string/list | 1.13 s | 1.8 MB |
| Rust: `opt-level=3` | malloc per string/list | 1.20 s | 2.3 MB |
| iyi: `--release` | GC heap, 3.2 s CPU | 1.59 s | 7.6 MB |
| Crystal: `--release` | Boehm GC heap, 4.0 s CPU | 1.79 s | 4.1 MB |

Trees pay only in Goose's layout; a classic object tree on tape (a TapeArray
per node) is slower than the heap. 4.6 MB JSON, 20 parses, 1 core, best of 7:

| tree layout (`--release`, 2026-10-18) | in ris now? | time | RSS | garbage |
|---|---|---|---|---|
| tape: Goose pool, children first | NO, test | 910 ms | 59 MB | 0 |
| heap: std/json `Any` tree | YES, std/json | 1113 ms | 99 MB | 31 MB |
| tape: `TapeArray` per node, stacked | NO, test | 1577 ms | 93 MB | 0 |
| tape: `TapeArray` per node, as parsed | NO, test | 2006 ms | 126 MB | 0 |

Garbage: heap bytes per parse left to the GC (16 GCs in 20 runs, timed).
NO, test: only here; ris has no pool type, `TapeArray#[]=` or tape JSON yet.

## Implementation and checks
* `src/iyi/`: `tape.iyi` containers, `prelude.iyi` mappings, GC roots.
* [TapeChecker](src/compiler/iyi/semantic/tape_checker.cr): storage types;
  [TapeLifetimeChecker](src/compiler/iyi/semantic/tape_lifetime_checker.cr):
  calls, yields, assignments, exits. `check_tape_captures`: procs.
* `test/ris/check.sh`: refused programs, exits, nesting, growth, fibers.

## Interfaces and remaining work
Use `to_s` at a lifetime boundary, not tape/heap variants of each method.
To call it stable: audit lifetime checks, specify pointer/FFI boundaries,
measure copy-out, GC scanning, long scopes (`Tape.local` bounds them).
