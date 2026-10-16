# ris: Rubyist In Stack memory with agents

**In short: Ruby in Rust with tape memory on the Go.** Nothing in ris is
Rust: each word names what ris takes from where. ris is an experimental fork
of [iyi](https://github.com/iyilang/iyi), which is built on
[Crystal](https://crystal-lang.org), and the first three words are iyi's:

* **Ruby**: how code reads. Blocks, unions, nil-safety, type inference.
* **in Rust**: strict edges. `pub` exports, `impl` traits, no reopened
  classes, errors as unions.
* **on the Go**: one binary for `fmt`, `test`, `vet`, `check`, `lsp` and
  `mcp`; fibers; one executable, `--static` if asked.
* **with tape memory**, ris's own, after Goose's data stacks: a hot path's
  objects use the fiber's tape and are reclaimed together. The rest
  stays on iyi's collected heap, so no library needs rewriting, and the
  compiler refuses a tape value wherever it could outlive its scope.

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

## Getting it

`make ris`, then `./bin/ris run samples/ris/hello.ri`; `test/ris/check.sh`
runs ris's checks. Source files end in `.ri`. Building needs what iyi needs
([README.iyi.md](README.iyi.md)): a Crystal compiler and LLVM.

## Tape memory

* `@[OnTape] struct` makes a tape type; the prelude has `TapeString`,
  `TapeWriter` and `TapeArray(T)` (`src/iyi/tape.iyi`).
* `Tape.scope { }` frees the fiber's tape when the block returns. It returns
  nil; a nested scope runs on the outer tape. A fiber switch swaps tapes.
* `Tape.local { }` always owns an independent temporary tape, restores
  the previous tape on exit (including early return and panic), and returns
  nil. Copy retained output with `.to_s` before leaving. Its mappings are
  eligible for reuse immediately. Outer `TapeString` values may be read;
  convert other outer tape values to owned data before entering. This
  conservative restriction prevents storing temporary values in outer tape
  objects until the compiler supports distinct tape lifetimes.
* Only tape types go on the tape. `Pointer` is outside the rules.

The compiler refuses a tape value (examples in `test/ris/refused/`) in a
class field, in a struct that is not `@[OnTape]`, in a class variable, as
another generic's type argument, captured by a proc or `spawn`, or assigned
to a variable outside its `Tape.scope`. See [the tape design](TAPE_DESIGN.md)
for lifetime rules, implementation details and open decisions.

## How fast

`samples/ris/respond.ri`: 1.6 million requests, each building a small object
and rendering it as JSON, written idiomatically in each language. Median of
9 rounds, x86_64 Linux, `-O3`:

| | time | peak memory |
|---|---:|---:|
| **ris, `@[OnTape]` types** | **0.71 s** | **1.7 MB** |
| Goose, inline DTO | 0.70 s | 2.0 MB |
| C++, `std::string` + `std::vector` | 1.01 s | 4.0 MB |
| Rust, `String` + `Vec` | 1.23 s | 2.3 MB |
| iyi, without tape | 1.59 s | 7.7 MB |
| Go, `string` + `[]Item` | 1.72 s | 8.6 MB |

One benchmark, the one tape suits best: many small objects that die
together. Without tape types a program runs as in iyi (1.35 s here, thanks to
a faster `String::Builder`), at two stores per fiber switch.

## Status and thanks

ris 0.1.0 is a prototype: tape types have what the benchmark needs; a tape
starts at 64 MiB and grows. Internals keep iyi's names so iyi merges.
Built on **Crystal** (Ary Borenszweig, Juan Wajnerman, Brian Cardiff, Manas
and the community), **iyi** (Serdar Dogruyol), **Goose** (Wouter van
Oortmerssen: data stacks, the benchmark, its C++ and Rust), **Ruby** (Yukihiro
Matsumoto) and C#'s `ref struct`. Developed with Claude. Apache 2.0, see
[LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
