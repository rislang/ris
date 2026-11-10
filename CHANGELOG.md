# Changelog

## 0.1.0 (unreleased)

The first version of ris, a prototype: a Ruby-like language whose data
lives on tape memory, with no GC. Built on iyi 0.19.1, a fork of Crystal
1.22.0-dev; internals keep iyi's names so iyi merges.

* Tape memory from Goose: bump-allocated, freed at once. Every def, loop
  round and block frees its own temporaries; main and each fiber have an
  implicit tape. There is no heap: heap allocation traps.
* The compiler refuses values outliving their scope; `copy_to(owner)`
  copies what must be retained (SPEC 1.1, 1.5, 1.9).
* Safety exceptions are marks with reasons in the code (`@[Ffi]`,
  `@[PointerUnsafe("…")]`, `@[TapeUnsafe]`); `ris unsafe` lists them.
* std on the caller's tape: HTTP server and head parser, JSON, time and
  HTTP dates, FileServer; Slim templates via github.com/domify/slim.
* One HTTP server entry, `Server.answer`: a handler's `call(req :
  Incoming, res : Outgoing)` over TLS, HTTP/2, compression, streamed
  bodies and upgrades; `Server.serve` and `Request` are gone.
* Messages between tasks through RisBoard and Atomic, replacing Channel,
  select and Mutex.
* iyi's tooling for agents: modules, imports by URL, fast modular
  rebuilds, `check`, `lsp`, `mcp`; `ris init` starts a project.
* `ris check`: one verb says whether the work is done. Parts format,
  deps, types, unused, test; `ris check PART` runs one. `--fix` (`-f`)
  fixes format and deps first; `ris check types --fix` applies the
  compiler's suggested edits. `ris init` writes an AGENTS.md that says
  so; MCP has `check` and `test`.
* Breaking: `ris ok`, `ris vet`, `ris fmt`, `ris fix`, `ris mod tidy`,
  `ris tool format` and `ris tool unreachable` are removed; `ris check`
  replaces them. `ris check FILE` now runs every part for
  FILE (`ris check types FILE` is the old meaning); `-f json` is
  refused: `--json` gives steps, the types step carries `diagnostics`.
  Step names are format, deps, types, unused, test (were fmt, tidy,
  check, vet, test). MCP's `ok` and `fix` tools are gone.
* `ris test -j N` and `ris check -j N` use the machine's cores (default
  `RIS_JOBS`, else the CPU count); types, unused and test run at once.
  Output keeps file and part order.
* `ris ok` shows each step's wall time and the total (`ok in 22.7s`);
  `--json` carries them as `seconds`.
* Runs on Linux x86_64 and aarch64, and macOS arm64 (built from source).
  Build with LLVM 23 or newer (LLVM.md).
* `ris --version` prints the ris, iyi and Crystal versions.
