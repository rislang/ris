# ris

ris is iyi plus Goose's tape memory. These rules are for every agent.

## Agent first

* Keep authorized work moving until its agreed stopping point. A status
  question, clarification or related setup task does not stop the main
  task: answer briefly, then resume it in the same turn.
* When managing another agent, collect its result, review and verify it,
  commit when authorized, then assign the agreed next TODO. Do not leave
  completed agent work waiting merely because a status reply was sent.
* Report whether work is running, blocked or complete. Do not imply that
  work continues after ending a turn unless an agent or process is
  actually running. Stop early only on a real blocker or the user's order.
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
* Goose has proven tape fast; the goal is tape everywhere. At the end of
  each Now step (TODO.md), time the ports with ris-bench's goose-evals.sh
  on minitest: one line per port in the commit body. A timing never fails
  a gate; nothing is timed per change.
* The rules: [SPEC.md](SPEC.md), ris's specification. Other languages
  are in [ris-bench](https://github.com/rislang/ris-bench), which keeps a
  copy of `samples/ris/respond.ri`: change both in one go.

## A library works on the caller's tape

It returns tape data on the caller's tape; the owning scope frees it all:

* Take input as a `String` and borrow it; never copy text to accept it.
* Write into the caller's `String::Builder`, or return a `String` or an
  `@[OnTape]` struct viewing the input bytes rather than copying them.
* Temporaries go on the caller's tape: a nested `tape` block shares it at
  no cost. Every def, loop round and block frees its own temporaries when
  it ends (SPEC 1.1); there is no `local_tape`.
* The caller decides what outlives its tape: `copy_to(owner)` on a `String`,
  `Array`, `@[OnTape]` struct or class. There is no heap: `to_heap` is a
  historical spelling of a copy on the current tape, to remove.
  Writing into the caller's `String::Builder` beats building, then copying.
* A def's result follows SPEC 1.5 and 1.9: end the def with the call, grow a
  local in place, or append to a parameter. A copy is always written.
* No raw pointers in an API: pass `String`, `String::Builder`, `Array` or an
  `@[OnTape]` struct. Outside `std/` the compiler refuses a `String`'s
  `to_unsafe` and `String.new(pointer, size)`; a caller reads with `[]`,
  `[start, count]`, `each_byte`. Only the FFI or socket call takes a pointer.
  In an `@[Ffi]` module `text.to_unsafe` may only be a `lib` fun's argument.
* In `std/` a def handing a pointer to the OS is a small `@[TapeUnsafe]`
  with a reason. `src/iyi/` is exempt.

Example: `HeadParser.parse_head(bytes : String, from : Int32, complete :
Bool, fields : Array(Field)) : ParsedHead | HeadError | Nil`: its answer and
the caller's *fields* view *bytes*. A web server keeps a request's bytes,
temporaries and response on one tape.

## Fast on the tape

* Nothing frees before its def, round or block ends: refill an `Array`
  field with `clear`, never a new one per call (the compiler refuses it).
* Size growing values from the input up front: each reserves its own
  address space, so growth never moves it. `RIS_TAPE_STATS=1` reports
  side transfers and growth moves: both should read 0.

## Upstream, documents, LLVM

* A change that does not need tape belongs in iyi: make it there first, or
  list it in [UPSTREAM.md](UPSTREAM.md).
* A type iyi does not have is Ris*, tape or not, so a reader sees what
  is new; it becomes Iyi* only when iyi takes it and ris merges it back.
  An iyi name whose meaning ris changes is renamed; one ris drops is
  removed, not kept beside its replacement (Channel, select and Mutex
  gave way to RisBoard and Atomic). The rest keep their Iyi* names for
  merges.
* Keep inherited documents in doc/archive/iyi/ and doc/archive/crystal/;
  iyi's draft spec is doc/archive/iyi/SPEC.md, cited as "iyi SPEC".
  SPEC.md is ris's specification; ris's own docs include CONTRIBUTING.md.
* Change SPEC.md only with a dated entry and its reason in
  [SPEC_CHANGELOG.md](SPEC_CHANGELOG.md), in the same commit.
* EGM is required: every SPEC change or design proposal gets an EGM
  review of its draft before SPEC.md or code changes, and a drift report
  after ([CONTRIBUTING.md](CONTRIBUTING.md), Design checks).
* Cite doc/reference/iyi/ for unchanged iyi rules, doc/reference/goose/
  for Goose designs, doc/reference/koja/ for messages between tasks.
  Record only ris differences; check snapshot versions.
* Build with LLVM 23 or newer: 21 and 22 miscompile ([LLVM.md](LLVM.md)).

## Length and commits

* Every dokument line is at most 80 characters: documents, commit
  messages, help text.
* No `Co-Authored-By` or other AI attribution lines in commits: most work
  is done with agents, so the line is noise. A clear subject, a short body.
