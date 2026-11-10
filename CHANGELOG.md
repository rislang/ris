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
  rebuilds, `check`, `fix`, `lsp`, `mcp`; `ris init` starts a project.
* `ris ok`: fmt, mod tidy, check, vet and test in one verdict; exit 0
  means the work is done, `next:` names the fix. Also an MCP tool, and
  `ris init` writes an AGENTS.md that says so.
* `ris test -j N` and `ris ok -j N` use the machine's cores (default
  `RIS_JOBS`, else the CPU count); `ris ok` runs check, vet and test at
  once. Output keeps file and step order.
* Runs on Linux x86_64 and aarch64, and macOS arm64 (built from source).
  Build with LLVM 23 or newer (LLVM.md).
* `ris --version` prints the ris, iyi and Crystal versions.
