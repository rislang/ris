# ris tape memory: one tape per fiber, beside iyi's GC

Decided 2026-10-19: iyi stays as it is (`String`, `Array`, `Hash`, classes
on the GC heap) and the tape is added beside it. Goose's data stacks
([Goose](https://github.com/aardappel/goose)) are the direction and the
yardstick; features follow measured needs. [SPEC.md](SPEC.md) is iyi's.

## The model
* `tape do … end` opens the running fiber's tape: bump allocation over
  mappings, chained when full, never moved. Allocation without an active
  tape ends the program. The block normally returns `nil`.
* Tape types: `Tape::String`, `Tape::String::Writer`, `Tape::Array(T)`,
  `Tape::Tree(T)` and `@[OnTape]` structs. The annotation constrains where
  a value may live; ordinary allocations still follow iyi's rules.
* Nested `tape` blocks share the active tape. Only its owning block
  releases it, on normal and early exits, including panic. Mappings are
  reused or unmapped; there is no per-object freeing.
* `local_tape do … end` always owns a separate tape, releases it at its
  end and restores the previous tape. Use it when temporaries must be
  freed before the outer block ends, rather than for every small call.
* Tapes follow fibers across switches; spawned fibers have their own.
  Each thread caches up to 64 spare mappings, with bounded warm pages.
* Tape storage is not GC-managed, but used tape words are scanned as
  roots: a tape value can hold a reference to an ordinary heap object.

## Lifetime and storage rules
No tape value survives the block that owns its storage:
* Tape values may be locals, arguments and results within that lifetime,
  `@[OnTape]` fields and `Tape::Array` elements; not class or plain struct
  fields, class variables or heap containers such as `Array(Tape::String)`.
* No proc, including a spawned block, captures one. Assignment, `return`,
  `break` and `yield` cannot carry one past its owning block.
* In `local_tape`, outer `Tape::String` values may be read. Other outer
  tape values, including mutable containers and `self`, cannot be used;
  prepare owned data before entering. Inner values cannot escape into
  outer variables or containers. Copying a struct does not copy its data.
* `Tape::String.new(text)` copies heap text onto the tape; `.view(text)`
  borrows its bytes. `[start, count]` borrows a slice; `[]` reads a byte.
* To retain text, call `to_s` inside an `@[Escape]` def while its source
  is alive. Interpolation and writing tape text into `String::Builder`
  or `IO::Memory` also require this annotation. It permits heap copies,
  not escaping tape values. Each helper making a copy needs its own mark.
* Pass tape text on, append to a tape writer, or write directly to a file
  or socket (`puts text`, `io << text`). Avoid tape -> heap -> tape copies.
* Pointer access (`to_unsafe`, `Tape::String.new(pointer, size)`) and heap
  copy checks exempt library code in `std/` and `src/iyi/`. These checks
  do not make arbitrary raw pointers safe.

## Layout: write the tape in order
A container grows in place only at the tape's end. A loop that grows an
existing container and also allocates other tape data is refused, even
through helper calls. Two growing writers are one example. Blocks are
conservatively treated as loops. Use one streaming writer/tree, or a
fixed-size array: `Tape::Array(T).new(count) { |i| ... }`.
A `Tape::Tree` stores a tree in document order (simdjson's layout):
4.6 MB JSON, 20 parses, 725 ms; std/json's `Any` 1081.

| median of 9, ris-bench | Goose | ris tape | ris heap |
|---|---|---|---|
| respond, 1.6M DTOs | 0.67 s, 2.0 MB | 0.67 s, 1.7 MB | 1.55 s, 7.6 MB |
| bintrees | 0.06 s, 7.9 MB | 0.10 s, 7.1 MB | 0.32 s, 24 MB |
| words | 0.22 s, 68 MB | 0.34 s, 90 MB | 0.54 s, 175 MB |
| graph_csr | 0.64 s, 109 MB | 1.06 s, 108 MB | 1.06 s, 174 MB |

These are recorded benchmark results, not new measurements.
C++ 0.97 s, Rust 1.18 s, Go 1.67 s on respond; see
[ris-bench](https://github.com/rislang/ris-bench).

## From Goose, when a benchmark needs it
* A tape per growing value; words and graph_csr size their arrays first.
* Bounds checks elided in loops; graph_csr's gap is this, not memory.
* Every scope freeing, results built in their destination, outlives and
  shrink checks; a `group`'s fibers on tapes of their parent's region.

## Implementation and checks
`src/iyi/tape.iyi`: types and scopes; `src/iyi/prelude.iyi`: `IyiRegion`.
`src/compiler/iyi/semantic/tape*checker.cr`: storage, lifetimes, layout,
raw pointers and heap copies. `bash test/ris/check.sh` checks refusals,
cleanup, nested/local scopes, growth, fibers and retained copies.
