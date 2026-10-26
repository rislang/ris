# ris

ris is iyi plus Goose's tape memory. These rules are for every agent.

## Agent first

* ris is made for the agent that writes a user's program: a choice is
  judged first by how well that agent works with it, so the code it writes
  is fast and safe without extra effort.
* A rule lives in the compiler, not in prose: an agent follows errors, so
  each refusal names the safe form that replaces the code.
* A safety exception is a mark with a reason in the code (`@[Ffi]`,
  `@[PointerUnsafe("…")]`), never a global switch; `ris unsafe` lists them.

## Tape first

* Move code onto tape wherever it pays: the compiler's runtime, `src/std/`
  (iyi's files included) and ris's own modules. Merging with iyi does not
  hold a change back; a conflict is resolved when iyi is merged.
* It pays where much short-lived data is made and dropped together: a
  request, a parse, a render, a response. What a caller retains is copied
  to a longer-lived owner with `copy_to` (e.g. `Program.tape`); no heap.
* Speed measurement is off for now: Goose has proven tape fast; the goal is
  tape everywhere. Whole-project speed tests come later, not per change.
* Rules for tape values: [TAPE_SPEC.md](TAPE_SPEC.md). Other languages
  are in [ris-bench](https://github.com/rislang/ris-bench), which keeps a
  copy of `samples/ris/respond.ri`: change both in one go.

## A library works on the caller's tape

It returns tape data on the caller's tape; the owning scope frees it all:

* Take input already on the tape (`Str`), not a `String` copy of it.
* Write into the caller's `Str::Builder`, or return a `Str` or an
  `@[OnTape]` struct viewing the input bytes rather than copying them.
* Temporaries go on the caller's tape: a nested `tape` block shares it at
  no cost. No `local_tape` per call; it costs more than small work saves.
* The caller decides what outlives its tape: `copy_to(owner)` on a `Str`,
  `Ary` or `@[OnTape]` struct. `to_heap`, `to_s` to a `String` and
  `@[TapeToHeap]` are migration paths, each a marked heap site to remove.
  Writing into the caller's `Str::Builder` beats building, then copying.
* No raw pointers in an API: pass `Str`, `Str::Builder`, `Ary` or an
  `@[OnTape]` struct. Outside `std/` the compiler refuses a `Str`'s
  `to_unsafe` and `Str.new(pointer, size)`; a caller reads with `[]`,
  `[start, count]`, `each_byte`. Only the FFI or socket call takes a pointer.
* A `String` API beside it is migration only, built on the tape one; new
  code takes `Str`. In `std/` a def handing a pointer to the OS is a small
  `@[TapeUnsafe]` with a reason. `src/iyi/` is exempt.

Example: `HTTP.parse_head(bytes : Str) : ParsedHead | ParseError`, its
fields views into *bytes*; `parse_request(text : String)` stays only until
migrated. A web server keeps a request's bytes, temporaries and response
on one tape.

## Fast on the tape

* Nothing frees before its block ends: refill an `Ary` field with `clear`,
  never a new one per call (the compiler refuses it).
* Size growing values from the input up front: each reserves its own
  address space, so growth never moves it. `RIS_TAPE_STATS=1` reports
  side transfers and growth moves: both should read 0.

## Upstream, documents, LLVM

* A change that does not need tape belongs in iyi: make it there first, or
  list it in [UPSTREAM.md](UPSTREAM.md).
* Keep inherited documents in doc/archive/iyi/ and doc/archive/crystal/;
  SPEC.md stays at the root as an inherited language reference.
  ris's own docs include CONTRIBUTING.md; TAPE_SPEC.md rules tape memory.
* Change TAPE_SPEC.md only with a dated entry and its reason in
  [TAPE_SPEC_CHANGELOG.md](TAPE_SPEC_CHANGELOG.md), in the same commit.
* Cite doc/reference/iyi/ for unchanged iyi rules, doc/reference/goose/
  for Goose designs. Record only ris differences; check snapshot versions.
* Build with LLVM 23 or newer: 21 and 22 miscompile ([LLVM.md](LLVM.md)).

## Length and commits

* Every dokument line is at most 80 characters: documents, commit messages, help text.
* No `Co-Authored-By` or other AI attribution lines in commits: most work
  is done with agents, so the line is noise. A clear subject, a short body.
