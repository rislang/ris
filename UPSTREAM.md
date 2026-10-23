# Upstream to iyi

ris is iyi plus tape memory. A change that does not depend on tape belongs
in iyi: make it there first and merge it into ris, or, if it was made in
ris, take it to iyi with `git cherry-pick`. Strike an entry off once iyi
has it.

## To take to iyi

* Refuse integer `/` directly in interpolation or before `to_s`, naming
  `//` and `a.to_f / b`. Tape interpolation stays in ris.

* Concurrent builds of the same entry share mutable object-cache paths.
  One can replace or remove another's objects before artifact assembly:
  std/http's artifact lost the TLS client unit during parallel gates.
  Separate `IYI_CACHE_DIR`s make the producer and consumer pass; make
  cache publication safe across builds in iyi.

* v0.18.0 integration: explicit std imports in new modules and exercises,
  required by ris's per-file extension checks (`std/int`, `std/text`,
  `std/indexable` and others reported by the compiler), including the
  AEAD and CSV gates' generated oracles. HTTP's import audit includes
  those pure modules and sorts independently of locale.
* Dependency audits: LLVM 23's local `_PROCEDURE_LINKAGE_TABLE_` marker
  is not a dynamic import; allow it in the Linux toolchain floor.
* Exercise proofs: bypass a hosts result without injecting an unimported
  extension; lower Linux x86-64's Adler cost bound to separate LLVM 23
  batched and per-byte reductions (1.3-1.8 vs 3.7-6.1 byte sums here).
* std/debug: the broken unwind-row proof may lose beta or alpha on
  LLVM 23; require either caller frame to be missing.

* `50745b97c` Optimize a single unit from its bitcode in an isolated
  context: LLVM 23 miscompiles the module optimized in place.
* `0d5fc458b` + `f7f7d3d9f` Warn on LLVM 21 and 22 (IndVarSimplify
  miscompile), recommend 23; `LLVM.md` (rename its ris wording).
* `7d3a1517f` std/time: the clock through the vDSO on x86_64 Linux.
* `1d4f7ed68` Say which manifest a build read when an import is not found.
* std/socket: `IyiSocket#write(first, second)`, two buffers in one
  `sendmsg`/`writev`. Written apart, a response's head and body wait on
  the client's delayed ACK (Nagle), 40 ms each (web, 2026-10-17). Take the
  `String` overload; the `Tape::String` one stays in ris.
* `IyiScheduler.current`: the running fiber inline, the first touch out of
  line. Two calls a `tape` made it 0.7% of respond (2026-10-18).

* std/json: a string with an escape no longer makes a substring per
  non-ASCII run (`StringBuffer#append(Pointer, Int32)`), and the writer's
  escapes are `JSON.each_escaped_byte`. The lexer's span mode, the tape `Writer`
  and `Document` stay in ris.
* `IyiFloatText.write(bits, buffer)` / `format_into`: a float's text into
  a buffer, `to_s` on top. Keep bounded copies as fixed stores so LLVM 23
  does not introduce libc `memcpy` on Darwin after the extraction.
  `Tape::String::Writer#append_float` stays in ris.
* Both are iyi's branch `json-float-from-ris` (`c02af8fac`), not merged.

## To make in iyi first

* std: `String#rchop`, `String#lchop(String)`; missing when a blog was
  written on web (2026-10-17).

* `String#[]` indexes bytes while `size` counts characters: at least say
  so in the docs and in a hint; a decision for iyi.
* `editors/vim`: named arguments and keys (`user_id: x`, `{id: 1}`) as
  Ruby's symbols, `iyiNamedArgument`, with its tests.
* std/aead `seal_at`/`open_at` and std/tls records opened and sealed in
  place (`TlsRecordCipher#seal_at`, `#open_at`): no tape, nothing per record.

## Stays in ris

* Tape: std/http `parse_head` and `ParsedHead`, the tape list in
  `IyiRegion`, `CLAUDE.md`'s tape rules.
