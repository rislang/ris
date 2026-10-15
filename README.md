# ris: Rubyist In Stack memory with agents

ris is an experimental fork of [iyi](https://github.com/iyilang/iyi), built
on [Crystal](https://crystal-lang.org): Ruby syntax, strict interfaces and tape.

* **Ruby**: how code reads. Blocks, unions, nil-safety, type inference.
* **in Rust**: `pub`, `impl`, closed classes and errors as unions.
* **on the Go**: one CLI (`fmt`, `test`, `check`, `lsp`, `mcp`), fibers.
* **with tape memory**, after Goose's data stacks: a hot path's objects use
  the fiber's tape and are reclaimed together. The rest stays on iyi's
  collected heap, and the compiler refuses a tape value that could outlive
  its scope.

```crystal
@[OnTape]
pub struct Order
  getter customer : TapeString
end
Tape.scope do
  body = render(make_order(1_i64)).to_s   # `to_s` copies out what is kept
end                                       # all tape storage reclaimed
```

## Getting it and tape memory

`make ris`, then `./bin/ris run samples/ris/hello.ri`; `test/ris/check.sh`
runs the checks. Sources end in `.ri`; `ris init` writes `ris.mod` (and
`ris.sum`), read before an iyi package's `iyi.mod`. Building needs a
Crystal compiler and LLVM ([README.iyi.md](README.iyi.md)).

* Tape types: `@[OnTape] struct`, `TapeString`, `TapeWriter`, `TapeArray`.
* `Tape.scope { }` frees the fiber's tape when the block returns; a nested
  scope runs on the outer tape. `Tape.local { }` runs on its own temporary
  tape and may read only the outer tape's `TapeString`s.
* The compiler refuses tape values in heap fields, containers, kept procs
  and assignments beyond their scope ([TAPE_DESIGN.md](TAPE_DESIGN.md)).

## How fast

`samples/ris/respond.ri`, 1.6M DTOs as JSON; median of 9, x86_64, `-O3`:

| | time | peak memory |
|---|---:|---:|
| **ris, `@[OnTape]` types** | **0.71 s** | **1.7 MB** |
| Goose, inline DTO | 0.70 s | 2.0 MB |
| C++ / Rust | 1.01 / 1.23 s | 4.0 / 2.3 MB |
| iyi / Go | 1.59 / 1.72 s | 7.7 / 8.6 MB |

Slang 2.0.3 vs its ris port, 200k pages: text 0.29 to 0.07 s, attr 0.72 to 0.43.

## Campfire, preliminary

**The Campfire port is not finished; its numbers will change.** The ris
port (`../once-campfire-ris/bench`) answers its busiest page, 40 messages
and 364,500 bytes, byte for byte as the Rust port does, same SQLite
database. 2026-10-15, 16-core Linux; p99 at 64 connections. `raw` is
ris's own minimal HTTP loop (iyi-web: 9,182/s). ¹ Approximate.

| one core (`ab`) | ris raw | Rust | Go | Rails¹ |
|---|---|---|---|---|
| Requests/s | **10,692** | 7,311 | 5,489 | 444 |
| Median | **0.135 ms** | 0.214 ms | 0.214 ms | 5.5 ms |
| Slowest (p99) | **7 ms** | 76 ms | 167 ms | 226 ms |
| Memory | 17 MB | 76 MB | 16 MB | 309 MB |

| eight cores (`loadgen`) | ris | Rust | Go |
|---|---|---|---|
| Requests/s | **34,762** | 23,180 | 11,944 |
| Median | **0.157 ms** | 0.234 ms | 0.472 ms |
| Slowest (p99) | **5.8 ms** | 7.5 ms | 24.7 ms |
| Memory | 34 MB | 76 MB | **29 MB** |

## Status and thanks

ris 0.1.0 is a prototype; internals keep iyi's names so iyi merges. Built
on **Crystal** (Ary Borenszweig, Juan Wajnerman, Brian Cardiff, Manas and
the community), **iyi** (Serdar Dogruyol), **Goose** (Wouter van
Oortmerssen), **Ruby** (Yukihiro Matsumoto) and C#'s `ref struct`.
Developed with Claude. Apache 2.0: [LICENSE](LICENSE), [NOTICE.md](NOTICE.md).
