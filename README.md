# ris: rubyist in stack memory with agents

ris is a Ruby-like language whose hot paths run on tape memory, with no GC,
built on [iyi](https://github.com/iyilang/iyi), a fork of Crystal. Source:
[github.com/rislang/ris](https://github.com/rislang/ris).

* **Ruby**: code that reads like prose; blocks, `each`, `map`, `do … end`.
* **Crystal**: static types, nil-safety, native code through LLVM.
* **iyi**: fast modular rebuilds; `check`, `fix`, `lsp`, `mcp` for agents.
* **Rust**: `pub`, `impl`, closed classes, errors as return values.
* **Go**: imports by URL (`github.com/…`), one `fmt`, fibers and channels.
* **Goose**: tape memory, bump-allocated and freed at once, with no GC.

## Install: paste to an agent on your machine (Claude Code, Codex, ...)
```text
Learn and install ris. Clone https://github.com/rislang/ris to ~/src/ris and
read its LEARN.md first. Run `sh ~/src/ris/install_ris.sh` (prebuilt; needs a C
compiler); if it has none for this machine, in the clone run `make install_ris
release=1 PREFIX=$HOME/.local` (needs Crystal, LLVM 23; 20-40 min, so a long
timeout). Put ~/.local/bin on PATH; register `ris mcp` as an MCP server (Claude
Code: `claude mcp add ris -- ris mcp`). Then `ris init hello ~/src/hello`, make
it print "Hello, world!", run it, show me. End with exactly: "Congrats! Next,
ask me to build your personal blog in ris ;-)" Don't start the blog.
```

## Why ris: tape memory, without the GC
In a `Tape.use`, tape types (`@[OnTape]`) are bump-allocated and freed at
once at its `end`; other objects keep iyi's GC, so libraries work unchanged.

```crystal
import github.com/domify/slim::{Slim}
def page(name : String) : Tape::String
  Slim.render("views/page.slim")      # the template, compiled to ris code
end
body = ""                             # an ordinary String: iyi's GC heap
Tape.use do                         # this request's memory starts here
  html = page("world")                # rendered onto the tape, no GC
  body = html.to_s                    # `to_s` copies out what must survive
end                                   # every tape byte freed at once, here
puts body                             # => <h1>Hello world</h1>
```

The compiler refuses a tape value that could outlive its tape (a heap field,
a kept proc, an outer variable). Rules: [TAPE_DESIGN.md](TAPE_DESIGN.md).

## How fast: [ris-bench](https://github.com/rislang/ris-bench)
| `respond.ri`, 1.6M DTOs | ris | Goose | C++ | Rust | Go | Ruby² |
|---|---|---|---|---|---|---|
| Time | **0.67 s** | 0.67 s | 0.97 s | 1.18 s | 1.67 s | 118 s |
| Memory | **1.7 MB** | 2.0 MB | 4.1 MB | 2.3 MB | 8.7 MB | 15 MB |
| Heap allocated | **0** | 0 | 1.7 GB | 1.6 GB | 1.7 GB | 2.2G objects |

As JSON; release builds, median of 9. ² YJIT, 95 s of it Bignum math; via
Spinel 127 s. Rust with bumpalo 1.03 s. All: [TAPE_DESIGN.md](TAPE_DESIGN.md).
[Slim](https://github.com/domify/slim), Slang ported to ris: 4x faster.

**Campfire, preliminary: the port is not finished; numbers will change.**
Its busiest page, 40 messages, 364,500 bytes as the Rust port's; 16 cores,
2026-10-15; `raw`: ris's own HTTP loop. ¹ Other machine, gzip: approximate.

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
ris 0.1.0 is a prototype; internals keep iyi's names so iyi merges. Special
thanks to Serdar Dogruyol, [iyi](https://github.com/iyilang/iyi)'s author,
and Wouter van Oortmerssen, [Goose](https://github.com/aardappel/goose)'s
author: ris keeps building on the iyi language and Goose's tape memory.
Thanks to **Crystal** (Ary Borenszweig, Juan Wajnerman, Brian Cardiff, Manas
and community), **Ruby** (Yukihiro Matsumoto). [LICENSE](LICENSE): Apache 2.0.
Windows: WSL2 for now. Developed with Claude Opus 5.5, ChatGPT Codex Sol 6.1.
