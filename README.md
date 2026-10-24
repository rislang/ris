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
Parse a request and build its response on one tape: bump-allocated, freed at
once when `tape` ends, with no GC work. HTTP, JSON and Slim all work on it:

```crystal
import std/http::{Server, ParsedHead}  # supports tape memory
import std/json::{JSON}                # supports tape memory
import github.com/domify/slim::{Slim}  # supports tape memory
tape do # one tape for this request
  bytes = "GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n".as_tape
  req = Server.parse_head(bytes) # its fields are views into the bytes
  if req.is_a?(ParsedHead)
    body = Str.build do |writer| # JSON written on the tape
      writer.json { |json| json.object { json.field "path", req.target } }
    end
    puts body                             # => {"path":"/hello"}
    puts Slim.render("views/page.slim")   # h1= req.target => <h1>/hello</h1>
  end
end # the tape is freed
```

Other objects use iyi's GC. Tape values go to a file or socket uncopied;
`Server.answer` gives each request a tape. The compiler refuses a tape value
outliving it; `text.to_heap` copies what must. [TAPE_DESIGN.md](TAPE_DESIGN.md).

## How fast: [ris-bench](https://github.com/rislang/ris-bench)
| `respond.ri`, 1.6M DTOs | ris | Goose | C++ | Rust | Go | Ruby² |
|---|---|---|---|---|---|---|
| Time | **0.67 s** | 0.67 s | 0.97 s | 1.18 s | 1.67 s | 118 s |
| Memory | **1.7 MB** | 2.0 MB | 4.1 MB | 2.3 MB | 8.7 MB | 15 MB |
| Heap allocated | **0** | 0 | 1.7 GB | 1.6 GB | 1.7 GB | 2.2G objects |

As JSON; release, median of 9. ² YJIT, 95 s Bignum math; Spinel 127 s. Rust
with bumpalo 1.03 s. [Slim](https://github.com/domify/slim) (Slang): 4x faster.

**Campfire port, the whole app:** busiest page, 40 messages, 364,500 bytes;
2026-10-17, Ryzen 7 PRO 6850U, 64 connections, three 10 s runs.
| | 1 core req/s | p99 | memory | 8 CPUs req/s | p99 | memory |
|---|---|---|---|---|---|---|
| ris | 6,847-7,168 | **10-11 ms** | **20 MB** | **21,822-22,040** | 9-11 ms | 172 MB |
| Rust | **7,066-7,187** | 16 ms | 52 MB | 20,639-21,497 | **6-7 ms** | **70 MB** |
| Rails¹ | 444 | 226 ms | 309 MB | | | |

¹ Other machine, gzip: approximate. ris on 8 CPUs: 8 processes, one port.

<img src="doc/assets/tape-heap.anim.svg" width="742" alt="respond: tape 0.67 s
  / 1.7 MB; heap 1.55 s / 7.6 MB; 5x slower playback; a block is 0.05 MB">

## Status and thanks
ris 0.1.0 is a prototype; internals keep iyi's names so iyi merges. Thanks to
Serdar Dogruyol ([iyi](https://github.com/iyilang/iyi)), Wouter van Oortmerssen
([Goose](https://github.com/aardappel/goose)), **Crystal** (Ary Borenszweig,
Juan Wajnerman, Brian Cardiff, Manas and community) and **Ruby** (Yukihiro
Matsumoto). [LICENSE](LICENSE): Apache 2.0. Windows: WSL2 for now. Developed
with Claude Opus 5.5, ChatGPT Codex Sol 6.1.
