# ris tape memory: current design

GC plus optional tape is decided; the tape is experimental, no proof of memory
safety. [SPEC.md](SPEC.md) is iyi's, unchanged; example: [README.md](README.md).

## Allocation and ownership
Objects use iyi's GC heap. Tape is opt-in: `Tape::String` (and its
`Writer`), `Tape::Array(T)`, `Tape::Tree(T)` go on the running fiber's tape
(saved on a switch); `@[OnTape]` marks a struct tape-bearing, not moved. Tape
allocation outside `Tape.scope` or `Tape.local` ends the program. Bump-pointer;
64 MiB of address space first (written pages resident), then larger; 64 spares.

Only the outermost `Tape.scope` reclaims, on every exit (panic too); nested
scopes share it. `Tape.local` always takes its own tape, released on every
exit; a `Tape.scope` inside one shares it. A non-tape `break` may leave.

## Lifetime and storage rules
The invariant: no safe tape-bearing value survives reclamation of the
scope or local tape that owns its storage.

* Tape values may be locals, arguments/results within that lifetime,
  `@[OnTape]` struct fields and `Tape::Array(T)` elements; not class or plain
  struct fields, class variables or ordinary containers (`Array(Tape::String)`).
* No proc, spawned block included, may capture a tape-bearing value.
* Assignment, `return`, `break` (in unions or tuples too) carry none past its
  scope; synchronous `yield` alike. Nested scopes share one lifetime.
* `Tape.local` starts a new lifetime: its values reach no outer locals,
  returns or yield bindings. It may read outer `Tape::String`s; other outer
  tape values, `self` too, become owned data first (lifetimes are untyped).
* `Tape::String#to_s : String` copies into GC storage. Raw pointers and
  internal allocator calls are outside the contract.

Copying a `Tape::Array` or a writer aliases its state. Growth off the top
copies (element references are not stable). Tape words are GC roots.

## Layout: write the tape in order
Tape pays when written in order: one growing value at the top, all else
written once. Streaming pays most: `samples/ris/respond.ri`, 1.6M DTOs as
JSON, one `Tape::String::Writer` a response; median of 9, 2026-10-18,
release, as [ris-bench](https://github.com/rislang/ris-bench)'s `run.sh` builds:

| respond, DTO | memory | GCs | heap allocated | time | RSS |
|---|---|---|---|---|---|
| ris (LLVM 21) | tape | 0 | 0 | 0.67 s | 1.7 MB |
| Goose | own data stacks | 0 | 0 | 0.67 s | 2.0 MB |
| C++ | malloc, free | 0 | 1.7 GB | 0.97 s | 4.1 MB |
| C | malloc, free | 0 | 1.4 GB | 1.11 s | 1.8 MB |
| Rust | malloc, free | 0 | 1.6 GB | 1.18 s | 2.3 MB |
| iyi | GC heap | 658 | 2.8 GB | 1.55 s | 7.6 MB |
| Go | GC heap | 478 | 1.7 GB | 1.67 s | 8.7 MB |
| Crystal | Boehm GC heap | 3492 | 3.7 GB | 1.79 s | 4.1 MB |
| Ruby YJIT (95 s Bignum math) | GC heap | 443k | 2.2G objects | 118 s | 15 MB |
| Ruby via Spinel (Bigint math) | GC heap, malloc | * | 24 GB | 127 s | 4.9 MB |

\* Spinel's GC count could not be measured. Rust with a bumpalo arena per
request: 1.03 s, no heap; an add-on crate with `'b` lifetimes everywhere, not
built in, and little gain (`write!` costs more).

A tree pays in one `Tape::Tree` in document order (simdjson's layout), and a
classic object tree on tape is slower than the heap. 4.6 MB JSON, 20 parses:

| tree, 1 core, best of 7 | in ris now? | GCs | heap/parse | time | RSS |
|---|---|---|---|---|---|
| tape: `Tape::Tree`, document order | type YES | 0 | 0 | 725 ms | 54 MB |
| tape: Goose pool, children first | NO | 0 | 0 | 871 ms | 59 MB |
| heap: std/json `Any` tree | YES, std/json | 16 | 31 MB | 1081 ms | 99 MB |
| tape: `Tape::Array` per node, stacked | NO | 0 | 0 | 1328 ms | 83 MB |
| tape: `Tape::Array` per node, as parsed | refused | 0 | 0 | 1749 ms | 116 MB |

std/json too: `JSON.parse(Tape::String)` 675 ms and no heap, `Any` 840 ms
(escapes, floats); `JSON.build` into a writer 2.9x as fast. No YAML yet.

## Implementation, checks and remaining work
* `src/iyi/`: `tape.iyi` containers, `prelude.iyi` mappings, GC roots.
* [TapeChecker](src/compiler/iyi/semantic/tape_checker.cr): storage types;
  [TapeLifetimeChecker](src/compiler/iyi/semantic/tape_lifetime_checker.cr):
  calls, yields, exits; procs; TapeLayoutChecker, TapePointerChecker.
* `test/ris/check.sh`: refused programs, exits, nesting, growth, fibers.
* `to_s` at a lifetime boundary. To call it stable: audit lifetime checks,
  pointer/FFI boundaries, copy-out, GC scanning, long scopes (`Tape.local`).
