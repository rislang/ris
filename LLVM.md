# LLVM

ris builds with **LLVM 23** (preferred) or LLVM 20 and older. The Makefile
refuses LLVM 21 and 22.

## Why not 21 and 22

LLVM 21 and 22 miscompile a loop exit in IndVarSimplify: the loop leaves
with the value of its first iteration (`%.first_iter`) instead of the last.
`--release` code computes wrong results, for example `"9".to_i?` gives
`nil` and std/http rejects valid status codes. A plain C program reproduces
it, so the bug is in LLVM, not in ris. LLVM 23.1 has it fixed.

## Building

The finder skips 21 and 22. When the system llvm-config is one of them,
point the build at LLVM 23 explicitly:

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

## Debugging codegen

* `IYI_LLVM_ARGS="-opt-bisect-limit=N"` passes options to LLVM.
* `IYI_DUMP_PREOPT=FILE` writes the module before optimization
  (`FILE` bitcode and `FILE.ll`).
* `IYI_VERIFY=FILE` runs the LLVM verifier and writes its result.
