# ris tape memory: one tape per fiber, beside iyi's GC

Decided 2026-10-19: iyi stays as it is (`String`, `Array`, `Hash`, classes
on the GC heap) and the tape is added beside it. Goose's data stacks
([goose_spec.md](https://github.com/aardappel/goose)) are the direction and
the yardstick; a part of them comes when a benchmark shows the need, not
before. [SPEC.md](SPEC.md) is iyi's, unchanged.

## The model
* `tape { }` gives the running fiber a tape: one bump pointer over
  reserved address space, chained when it fills, never moved. A reader
  sees where the tape is; outside a block a tape value ends the program.
* Tape types: `Tape::String` (and its `Writer`), `Tape::Array(T)`,
  `Tape::Tree(T)`, structs marked `@[OnTape]`. All else is on the heap.
* Only the outermost block frees, at once, on every exit (panic too);
  nested blocks share it, so a library opens one at no cost. Work whose
  temporaries should not wait for the outer end takes `Tape.local`, a
  tape of its own freed when its block ends (web's intake, Slim).
* A fiber's tape is its own, saved on a switch; a spawned fiber has one of
  its own. 64 warm spares keep the next block's pages written.

## Lifetime and storage rules
No tape value survives the block that owns its storage:
* Tape values may be locals, arguments and results within it, `@[OnTape]`
  fields and `Tape::Array` elements; not class or plain struct fields,
  class variables or `Array(Tape::String)`.
* No proc, a spawned block included, captures one. Assignment, `return`,
  `break` and `yield` carry none past the block.
* `to_s` copies into a heap String. Raw pointers stay in `std/`.

## Layout: write the tape in order
One value grows at the tape's end; all else is written once. Two values
growing in turn in a loop are refused (TapeLayoutChecker): each growth of
the other would copy it. A tree pays as one `Tape::Tree` in document order
(simdjson's layout): 4.6 MB JSON, 20 parses, 725 ms; std/json's `Any` 1081.

| median of 9, ris-bench | Goose | ris tape | ris heap |
|---|---|---|---|
| respond, 1.6M DTOs | 0.67 s, 2.0 MB | 0.67 s, 1.7 MB | 1.55 s, 7.6 MB |
| bintrees | 0.06 s, 7.9 MB | 0.10 s, 7.1 MB | 0.32 s, 24 MB |
| words | 0.22 s, 68 MB | 0.34 s, 90 MB | 0.54 s, 175 MB |
| graph_csr | 0.64 s, 109 MB | 1.06 s, 108 MB | 1.06 s, 174 MB |

A request, a parse, a render grow one value at a time: there one tape
already matches Goose. C++ 0.97 s, Rust 1.18 s, Go 1.67 s on respond.

## From Goose, when a benchmark needs it
Each closes a measured gap; none is planned before one does.
* An inner block that frees its part (bintrees keeps its long tree on the
  heap for want of it). Needs a check that an inner value goes into no
  outer container.
* A tape per growing value, so several grow at once (words and graph_csr
  size their arrays first instead).
* Bounds checks elided in loops: graph_csr's gap is this, not memory.
* Every scope freeing, a hidden stack base per function, results built
  in their destination (goose_spec §7.3, App. E), Goose's outlives and
  shrink checks (§9, §5.1).
* A `group`'s fibers on tapes of their parent's region, read in place.

## Implementation and checks
* `src/iyi/tape.iyi`: `tape`, the types; `prelude.iyi`: `IyiRegion`.
* [TapeChecker](src/compiler/iyi/semantic/tape_checker.cr): storage types;
  [TapeLifetimeChecker](src/compiler/iyi/semantic/tape_lifetime_checker.cr):
  calls, yields, exits; TapeLayoutChecker; TapePointerChecker.
* `test/ris/check.sh`: refused programs, exits, nesting, growth, fibers.
