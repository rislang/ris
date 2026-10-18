# LLVM

Use **LLVM 23** or newer. ris still builds with older LLVM, but on 21 and
22 the Makefile warns: they miscompile some code.

## Why not 21 and 22

LLVM 21 and 22 miscompile a loop exit in IndVarSimplify: the loop leaves
with the value of its first iteration (`%.first_iter`) instead of the last.
`--release` code computes wrong results, for example `"9".to_i?` gives
`nil` and std/http rejects valid status codes. A plain C program reproduces
it, so the bug is in LLVM, not in ris. LLVM 23.1 has it fixed.

## Building

When the system llvm-config is older, point the build at LLVM 23:

    make ris LLVM_CONFIG=/path/to/llvm-23/bin/llvm-config

Prebuilt LLVM 23: https://github.com/llvm/llvm-project/releases

## Known workaround on LLVM 23

Optimizing the module in place, in the context it was built in, gave
wrong code on LLVM 23 (instcombine dropped half of a comparison). The
same module read back from bitcode into a fresh context optimizes
correctly. So every unit is optimized from its bitcode in an isolated
context (`compile(isolate_context: true)` in `compiler.cr`), as threaded
codegen already did. The deeper cause is not found yet; a suspect is the
`LibLLVM` bindings, inherited from Crystal, which does not support LLVM 23
yet. Don't remove the workaround without finding the cause.

## Tried: alias scopes for Tape::String::Builder

`!alias.scope`/`!noalias` on a writer's state and data (primitives refused
outside `tape.iyi`) left `push` unchanged (2026-10-18). The cursor already
stays in a register, as the byte is stored before the cursor; the cursor
store and the limit load stay in the loop because the `grow` call on the
slow path may write the state, which alias metadata cannot change. Not
kept: the gap to Goose is that capacity check, not aliasing. On LLVM 23
`samples/ris/respond.ri` runs 8.64G instructions, on LLVM 21 9.07G.

## Debugging codegen

* `IYI_LLVM_ARGS="-opt-bisect-limit=N"` passes options to LLVM.
* `IYI_DUMP_PREOPT=FILE` writes the module before optimization
  (`FILE` bitcode and `FILE.ll`).
* `IYI_VERIFY=FILE` runs the LLVM verifier and writes its result.
