# Contributing to ris

ris is iyi plus Goose's tape memory. Read [AGENTS.md](AGENTS.md) first,
then [LEARN.md](LEARN.md) and [TAPE_SPEC.md](TAPE_SPEC.md). The target is
ris programs without a collector; the current migration is recorded in
TAPE_SPEC.md. The compiler is still built with Crystal.

## Build

Use a Crystal bootstrap compiler, LLVM 23 or newer, a C/C++ toolchain and
libgc for the compiler's default build. LLVM 21 and 22 miscompile code;
see [LLVM.md](LLVM.md).

```sh
make ris LLVM_CONFIG=/path/to/llvm-23/bin/llvm-config
./bin/ris run samples/ris/respond.ri
```

`./bin/ris` is the ris entry point. Internals retain iyi's names to make
upstream merges manageable. `./bin/crystal` runs the inherited Crystal
compiler and specs.

## Check the change

Run the relevant program or spec first. For tape rules, add an accepted
example in `test/ris/` and a rejected example in `test/ris/refused/` when
applicable; each refusal must name the safe replacement.

Run larger builds and test suites on the `minitest` server. The helper
sends tracked and unignored files to an isolated source snapshot, builds
with LLVM 23 and keeps the build and test logs on the server:

```sh
bin/minitest-check build
bin/minitest-check run --no-gc test/ris/class_copy.ri
bin/minitest-check check
bin/minitest-check log
```

Use the same helper in agent tasks so one saved command permission covers
the workflow. It uses the existing `ssh minitest` connection.

For compiler or inherited runtime changes, run the relevant Crystal specs;
`make compiler_spec`, `make primitives_spec` and `make std_spec` run the
broader suites. Check formatting of changed Crystal files with
`./bin/crystal tool format --check PATH`.

## Design and review

* Library APIs work on the caller's tape: take `Str`, return tape views,
  or write into the caller's builder. Copy retained data at the boundary.
* Enforce safety in the compiler. Exceptions need a local mark and reason,
  never a global switch. Follow AGENTS.md for pointer and FFI boundaries.
* Changes independent of tape belong in iyi first, or in
  [UPSTREAM.md](UPSTREAM.md) until taken upstream.
* Per-change speed measurements are paused; move suitable work onto tape.
  Keep the respond sample and its ris-bench copy in sync.
* ris document lines are at most 80 characters, any length. Commit
  messages also wrap at 80; use a clear subject and no AI attribution.
* Preserve the Apache 2.0 licence and inherited copyright notices:
  [LICENSE](LICENSE), [NOTICE.md](NOTICE.md).

## Inherited references

[SPEC.md](SPEC.md) describes inherited language and compiler rules; it is
not the authority for ris's tape memory model. Historical iyi documents
are in [doc/archive/iyi/](doc/archive/iyi/), and Crystal's README is in
[doc/archive/crystal/](doc/archive/crystal/). Their plans and release notes
record the upstream projects, not ris's current roadmap.
