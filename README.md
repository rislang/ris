# ris: rubyist in stack memory with agents

ris is a Ruby-like language whose hot paths run on tape memory, with no GC.
Built on [iyi](https://github.com/iyilang/iyi), a fork of Crystal.
Source: [github.com/rislang/ris](https://github.com/rislang/ris).

* **Ruby**: code that reads like prose; blocks, `each`, `map`, `do … end`.
* **Crystal**: static types, nil-safety, native code through LLVM.
* **iyi**: fast modular rebuilds; `check`, `fix`, `lsp`, `mcp` for agents.
* **Rust**: `pub`, `impl`, closed classes, errors as return values.
* **Go**: imports by URL (`github.com/…`), one `fmt`, fibers and channels.
* **Goose**: tape memory, bump-allocated and freed at once, with no GC.

## Install: paste this to a coding agent on your machine

Claude Code, Codex, Cursor or any agent that runs commands on your machine.
```text
Learn and install ris (needs Crystal and LLVM). Clone
https://github.com/rislang/ris to ~/src/ris and read its LEARN.md and what
it lists. There run `make install_ris release=1 PREFIX=$HOME/.local`; put
~/.local/bin on PATH. Register `ris mcp` as an MCP server (Claude Code:
`claude mcp add ris -- ris mcp`). Last, build me a first app: `ris init
hello ~/src/hello`, make it print "Hello, world!", run it there, show me.
```

## Why ris: tape memory, without the GC

In a `Tape.scope`, tape types (`@[OnTape]`) are bump-allocated on a tape,
freed all at once at the scope's `end`. All other objects keep iyi's GC, so
iyi and Crystal libraries work unchanged.

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

The compiler refuses a tape value that could outlive its tape (a heap field,
a kept proc, an outer variable). Rules: [TAPE_DESIGN.md](TAPE_DESIGN.md).

## How fast

`samples/ris/respond.ri`, 1.6M DTOs as JSON, median of 9, `-O3`: **ris
0.71 s, 1.7 MB**; Goose 0.70 s, 2.0 MB; C++ 1.01 s, 4.0 MB; Rust 1.23 s,
2.3 MB; iyi 1.59 s, 7.7 MB; Go 1.72 s, 8.6 MB.
[Slim](https://github.com/domify/slim), Slang ported to ris: 4x faster.

**Campfire, preliminary: the port is not finished; numbers will change.**
The ris port answers its busiest page, 40 messages and 364,500 bytes, byte
for byte as the Rust port does. 16-core Linux, 2026-10-15; `raw` is ris's
own minimal HTTP loop (iyi-web: 9,182/s). ¹ Other machine, gzip: approximate.

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
Developed with Claude Opus 5.5, ChatGPT Codex Sol 6.1 and other models.
