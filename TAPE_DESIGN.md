# ris tape memory: one tape per fiber, beside iyi's GC

iyi stays as it is (`String`, `Array`, `Hash`, classes on the GC heap);
ris text defaults to tape; heap objects remain for retained data.
## The model
* Main and each spawned fiber own an implicit tape: bump allocation over
  mappings, chained when full, never moved. The tape is released when its
  body ends, including panic and exit. No `tape` block is required.
* Tape types, a closed set, three letters of the heap type: `Str`, `Ary(T)`,
  `Tre(T)`, their `Str::Builder`, `Str::Scanner`, `Ary::View`; `@[OnTape]`
  structs. Where a value may live is constrained; the rest is iyi's.
* `tape do … end` stays valid, shares the active tape and returns `nil`.
  Main or the spawned body owns it; a def, loop round or
  block (std's too, unless it holds raw pointers) that keeps nothing
  frees its part each time.
* `local_tape do … end` owns a separate tape, released at its end, for
  temporaries to free before the outer block ends.
* Tapes follow fibers across switches; spawned fibers have their own.
  Each thread caches up to 64 spare mappings, side regions too, warm.
* Tape storage is not GC-managed, but used tape words are scanned as
  roots: a tape value can hold a reference to an ordinary heap object.
## Lifetime and storage rules
No tape value survives the block that owns its storage:
* Tape values may be locals, arguments and results within that lifetime,
  `@[OnTape]` fields and `Ary` elements; not class or plain struct
  fields, class variables or heap containers such as `Array(Str)`.
* No proc, including a spawned block, captures one. Assignment, `return`,
  `break` and `yield` cannot carry one past its owning block.
* In `local_tape`, outer `Str` values may be read. Other outer
  tape values, including mutable containers and `self`, cannot be used;
  prepare owned data before entering. Inner values cannot escape into
  outer variables or containers. Copying a struct does not copy its data.
* In user `.ri` files, `"text"` is a zero-copy static `Str` view;
  `"text #{value}"` builds a `Str` on the active tape. std and iyi keep
  their old text rules. Macro code and annotations are compiler metadata.
* Read-only text APIs accept `Str`; String callers borrow with `as_tape`.
* Plain literals become static String in heap places, without a copy:
  String parameters/fields, constants and heap container literal entries.
  Other tape text needs `.to_heap`; locals stay Str. `Str.new` copies;
  `as_tape` borrows. String annotations never copy tape text.
* To retain a value, copy it by name while its source is alive: `to_heap`
  on a `Str`, an `Ary` or `Ary::View` (each element by its own `to_heap`),
  or an `@[OnTape]` struct that defines one. `to_s`, heap interpolation and
  writing into `String::Builder` need `@[TapeToHeap]`.
* Pass tape text on, append to a tape writer, or write directly to a file
  or socket (`puts text`, `io << text`). Avoid tape -> heap -> tape copies.
* `std/` is under these rules; only `src/iyi/` and a `std/` def marked
  `@[TapeUnsafe]` (refused elsewhere) may use raw pointers or copy freely.
## Layout: a tape per growing value
A container grows in place at the tape's end, else moves once to a region
of its own; `RIS_TAPE_STATS=1` counts moves and mappings at exit. `clear`
refills one. `Tre`, simdjson's order: 4.6 MB JSON ×20 in 725 ms.

| median of 9, ris-bench | Goose | ris tape | ris heap |
|---|---|---|---|
| respond, 1.6M DTOs | 0.67 s, 2.0 MB | 0.67 s, 1.7 MB | 1.55 s, 7.6 MB |
| bintrees | 0.06 s, 7.9 MB | 0.10 s, 7.1 MB | 0.32 s, 24 MB |
| words | 0.22 s, 68 MB | 0.34 s, 90 MB | 0.54 s, 175 MB |
| graph_csr | 0.64 s, 109 MB | 1.06 s, 108 MB | 1.06 s, 174 MB |
Recorded: C++ 0.97 s, Rust 1.18 s, Go 1.67 s on respond (ris-bench).
## Implementation and checks
`src/iyi/tape.iyi`, `IyiRegion` in `src/iyi/prelude.iyi`, the checks and
lowerings in `src/compiler/iyi/semantic/tape_*.cr`; `test/ris/check.sh`.
## Goose and ris
| Goose | ris tape | Why |
|---|---|---|
| No heap, no GC | Tape beside iyi's GC | Long-lived data stays on the GC |
| Scope end frees | Def, loop, block keeping nothing | Proven; not past `next` |
| One growing value, unmoved | Own region, moved once | No refs into elements |
| No annotations | Block lifetimes, `@[TapeToHeap]` | The GC holds the rest |
| Flat data, links | `Ary::Link`, `Str::Span`, `@[Tape::Flat]` | No pointers |
| Load checks every link | Checked when followed | Same safety, a later error |
| Built in place | `w.append(f(x))` writes in `w`; `puts "#{x}"` | No copy |
| Bounds checks elided | `each`, `while i < a.size` | The loop bounds `i` |
| Index types, `checkfree` | `a.values_at(b)`, `@[CheckFree]` | Checked once |
| Variable-size enums | No | Unions and the GC suffice |
| `reusable` pools | No | The GC holds unnested lifetimes |
| No escaping closures | For tape values only | Procs are heap values |
| Shared-nothing threads | No tape value on a channel | Send bytes on the heap |
| No growth across recursion | No such limit | Regions, not one stack |
