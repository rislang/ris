# ris: Rubyist In Stack memory with agents

ris is a Ruby-like language whose hot paths run on tape memory, with no GC.
Built on [iyi](https://github.com/iyilang/iyi), a fork of Crystal.
Source: [github.com/rislang/ris](https://github.com/rislang/ris).

* **Ruby**: how code reads, with Crystal's blocks, unions and nil-safety.
* **in Rust**: `pub`, `impl`, closed classes, errors as return values.
* **on the Go**: one CLI (`fmt`, `test`, `check`, `lsp`, `mcp`), fibers.

## Why ris: tape memory, without the GC

iyi and Crystal collect all garbage with a GC. ris adds **tape memory**,
after Goose's data stacks: in a `Tape.scope`, tape types (`@[OnTape]`) are
bump-allocated on a tape, and the whole tape is freed at the scope's `end`.
No GC allocates or frees it. All other objects keep iyi's GC, so iyi and
Crystal libraries work unchanged (the GC only scans the tape for pointers).

```crystal
import github.com/domify/slim::{Slim}

def page(name : String) : TapeString
  Slim.render("views/page.slim")      # the template, compiled to ris code
end

body = ""                             # an ordinary String: iyi's GC heap
Tape.scope do                         # this request's memory starts here
  html = page("world")                # rendered onto the tape, no GC
  body = html.to_s                    # `to_s` copies out what must survive
end                                   # every tape byte freed at once, here
puts body                             # => <h1>Hello world</h1>
```

Freeing by hand stays safe: the compiler refuses a tape value that could
outlive its tape (a heap field, `[] of TapeString`, a kept proc, an outer
variable). Rules: [TAPE_DESIGN.md](TAPE_DESIGN.md).

## Getting it

`make ris`, then `./bin/ris run samples/ris/hello.ri`. Sources end in `.ri`;
`ris init` writes `ris.mod`, read before an iyi package's `iyi.mod`. Needs
Crystal and LLVM ([README.iyi.md](README.iyi.md)); `test/ris/check.sh` checks.

## How fast

`samples/ris/respond.ri`, 1.6M DTOs as JSON, median of 9, `-O3`: **ris
0.71 s, 1.7 MB**; Goose 0.70 s, 2.0 MB; C++ 1.01 s, 4.0 MB; Rust 1.23 s,
2.3 MB; iyi 1.59 s, 7.7 MB; Go 1.72 s, 8.6 MB.
[Slim](https://github.com/domify/slim), Slang ported to ris: 4x faster.

**Campfire, preliminary: the port is not finished; numbers will change.**
The ris port answers its busiest page, 40 messages and 364,500 bytes, byte
for byte as the Rust port does. 16-core Linux, 2026-10-15; `raw` is ris's
own minimal HTTP loop (iyi-web: 9,182/s).
¹ Another machine, gzip on: approximate only.

| one core (`ab`) | ris raw | Rust | Go | Rails¹ |
|---|---|---|---|---|
| Requests/s | **10,692** | 7,311 | 5,489 | 444 |
| p99, 64 conn. | **7 ms** | 76 ms | 167 ms | 226 ms |
| Memory | 17 MB | 76 MB | 16 MB | 309 MB |

| eight cores (`loadgen`) | ris | Rust | Go |
|---|---|---|---|
| Requests/s | **34,762** | 23,180 | 11,944 |
| p99, 64 conn. | **5.8 ms** | 7.5 ms | 24.7 ms |
| Memory | 34 MB | 76 MB | **29 MB** |

## Status and thanks

ris 0.1.0 is a prototype; internals keep iyi's names so iyi merges. Thanks
to **Crystal** (Ary Borenszweig, Juan Wajnerman, Brian Cardiff, Manas and
community), **iyi** (Serdar Dogruyol), **Goose** (Wouter van Oortmerssen),
**Ruby** (Yukihiro Matsumoto), C#'s `ref struct`. Developed with Claude.
Apache 2.0: [LICENSE](LICENSE), [NOTICE.md](NOTICE.md).

Special thanks to Serdar Dogruyol, [iyi](https://github.com/iyilang/iyi)'s
author, for a friendly collaboration. ris keeps building on the iyi language.
