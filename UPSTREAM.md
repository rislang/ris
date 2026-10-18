# Upstream to iyi

ris is iyi plus tape memory. A change that does not depend on tape belongs
in iyi: make it there first and merge it into ris, or, if it was made in
ris, take it to iyi with `git cherry-pick`. Strike an entry off once iyi
has it.

## To take to iyi

* `50745b97c` Optimize a single unit from its bitcode in an isolated
  context: LLVM 23 miscompiles the module optimized in place.
* `0d5fc458b` + `f7f7d3d9f` Warn on LLVM 21 and 22 (IndVarSimplify
  miscompile), recommend 23; `LLVM.md` (rename its ris wording).
* `7d3a1517f` std/time: the clock through the vDSO on x86_64 Linux.
* `1d4f7ed68` Say which manifest a build read when an import is not found.
* std/socket: `IyiSocket#write(first, second)`, two buffers in one
  `sendmsg`/`writev`. Written apart, a response's head and body wait on
  the client's delayed ACK (Nagle), 40 ms each (web, 2026-10-17). Take the
  `String` overload; the `TapeString` one stays in ris.
* `IyiScheduler.current`: the running fiber inline, the first touch out of
  line. Two calls a `Tape.scope` made it 0.7% of respond (2026-10-18).

* std/json: a string with an escape no longer makes a substring per
  non-ASCII run (`StringBuffer#append(Pointer, Int32)`), and the writer's
  escapes are `JSON.each_escaped_byte`. The lexer's span mode, `TapeBuilder`
  and `TapeDocument` stay in ris.

## To make in iyi first

* std: `String#rchop`, `String#lchop(String)`, `Time#to_s(format)`;
  missing when a blog was written on web (2026-10-17).
* `String#[]` indexes bytes while `size` counts characters: at least say
  so in the docs and in a hint; a decision for iyi.

## Stays in ris

* Tape: std/http `parse_head` and `ParsedHead`, the tape list in
  `IyiRegion`, `CLAUDE.md`'s tape rules.
