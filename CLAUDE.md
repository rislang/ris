# ris

ris is iyi plus Goose's tape memory.

## Tape first

* Move code onto tape memory wherever it pays: the compiler's runtime, the
  std library (`src/std/`, iyi's files included) and ris's own modules.
  Merging with iyi does not hold a change back; a conflict is resolved when
  iyi is merged.
* It pays where much short-lived data is made and dropped together: a
  request, a parse, a render, a response. Keep what a caller retains on the
  heap, and copy it out with `to_s` at the boundary.
* Measure before keeping a change: the same work with and without tape,
  `--release`, interleaved runs, time and peak memory or bytes allocated.
  Keep it only for a clear gain, and say the numbers in the commit.
* Bytes allocated (`IyiMark.allocated_since`, collection off) are steadier
  than time on a busy machine; for time, take the fastest of several runs.
* Rules for tape values: [TAPE_DESIGN.md](TAPE_DESIGN.md).

## A library works on the caller's tape

As Slim does (`Slim.render`, `Slim.embed`), a library does not open a tape
of its own; the caller's `Tape.scope` owns all of it, freed at once:

* Take input already on the tape (`TapeString`), not a `String` copy of it.
* Write output into the caller's `TapeWriter`, or return a `TapeString` or
  an `@[OnTape]` struct the caller's scope owns, viewing the input bytes
  rather than copying them.
* Temporaries go on the caller's tape: a nested `Tape.scope` shares it at
  no cost. No `Tape.local` per call; it costs more than small work saves.
* The caller decides what to copy to the heap, and when.
* No raw pointers in an API: pass `TapeString`, `TapeWriter`, `TapeArray`
  or an `@[OnTape]` struct. The checker refuses a `TapeString` that leaves
  its scope, but not its `to_unsafe`: that pointer compiles and then reads
  the next scope's bytes. Only the library's own FFI or socket call takes
  one, never a caller.
* Keep the `String` API beside it, built on the tape one: it opens a
  `Tape.scope` (shared when the caller has one) and copies the result out.

Example: `HTTP.parse_head(bytes : TapeString) : ParsedHead | ParseError`,
with `ParsedHead`'s method, target and fields as views into *bytes*;
`parse_request(text : String)` stays, on top of it. A web server keeps a
request's bytes, temporaries and response on one tape per request.

## Upstream

* A change that does not need tape belongs in iyi: make it there first,
  or list it in [UPSTREAM.md](UPSTREAM.md) to take there later.

## Documents

* iyi's and Crystal's documents (SPEC.md, CHANGELOG.md, README.iyi.md,
  GC_DESIGN.md, …) stay as they are; ris's own are README.md, LEARN.md and
  TAPE_DESIGN.md, LLVM.md and UPSTREAM.md.

## LLVM

* Recommend and build with LLVM 23 or newer: 21 and 22 miscompile. Why, and
  the codegen workaround that must stay: [LLVM.md](LLVM.md).

## Length

* Every ris document is at most 80 lines. Condense, don't split.
* Every line of a command's help text (`ris help`, `ris <command> --help`)
  is at most 80 characters wide.

@AGENTS.md
