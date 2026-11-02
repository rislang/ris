# Upstream to iyi

ris is iyi plus tape memory. A change that does not depend on tape belongs
in iyi: make it there first and merge it into ris, or, if it was made in
ris, take it to iyi with `git cherry-pick`; strike entries once merged.
A Ris* type goes to iyi as Iyi*; ris renames it when the merge brings it
back.

## To take to iyi

* String#hash: iyi's byte-wise FNV-32 now takes 8 bytes a step, reads only
  the String's own bytes and spreads into the low bits Hash masks (ris's
  gates: test/ris/string_hash.ri, test/ris/src/iyi/string_hash_page.ri).

* std/tls: the Error implementation of TlsError.message recursed into
  itself, shadowing its formatter. Call the named formatter instead;
  check both a plain error and one carrying an alert.

* ris removed iyi's Crystal program compatibility mode, shard binding
  commands and tree migration command, including their options, samples,
  fixtures, specs and documentation. There is no transition path. Resolve
  future iyi merge conflicts by deleting these features. Artifact format
  v60 drops the old library selector byte and refuses older artifacts.
  The default installer ships ris and its prelude, without the Crystal
  command, installed manual pages or shell completions. Prelude overrides
  belong only to the developer Crystal surface; ris and iyi reject them.

* std/acme: optional task-owned HTTPClient for the directory and all
  signed exchanges. It lets independent sessions select TLS trust roots
  without changing HTTP.tls_config for other tasks. The caller closes
  the supplied transport; the protocol and default API stay unchanged.

* std/signal: syscall scratch buffers use fixed stack storage. Signal
  lists use ris's tape Array; keep iyi's heap Array variant in iyi.

* std/socket: optional SO_REUSEPORT on Linux and Darwin, with explicit
  refusal elsewhere; value-returning listen_result closes failed setup
  descriptors and lets servers distinguish setup failure from a panic.
  Task-owned socket state and copied HTTP configuration stay in ris.

* `IyiTask#wait(ms : Int32)` observes completion without consuming the
  result or cancelling the task. Each reader has its own timer; answers
  are Nil for Done, TimedOut or Cancelled. `value` still reads the result.

* Migration bang rewrites: narrow the optional definition-name capture
  before checking or removing its bang suffix in the compiler spec build.

* Channel: waking a receiver does not release a buffered slot, so the
  ring never grows; a full send parks and a receive refills its slot.

* std/int: popcount and the zero counts through LLVM's bit intrinsics,
  carried by `RisBits` (bf760fcb3), which goes to iyi as `IyiBits`.

* std/math: use StaticArray for all fixed numeric constant tables,
  preserving their literal bits without startup heap allocations.

* Let Mutex subclasses acquire and release their lock in synchronous
  methods, without materializing a callback over borrowed arguments.
* Log.with_context yields directly to its synchronous block instead of
  materializing a proc; retain context restoration on every exit.

* Stack-allocate capture environments used only by defer callbacks;
  retain escaping storage when ordinary closures share the captures.
* Panic source-line diagnostics use a stack buffer so formatting cannot
  allocate before defer cleanup runs.
* HTTP 100-continue: store pending state in BodyReader and write through
  its held connection, replacing the retained transport-capturing proc.
  Preserve the first wait, at-most-once send and existing failure mapping.
* std/json: parse whole documents with an explicit container and pending
  key stack, avoiding task stack overflow at 256 levels in plain builds.
  Use an Array in iyi; ris keeps the stack on the caller's tape.

* Cleanup reads current receivers; recursive panic and task caps are fatal.
  Fault dispositions use stack storage; signal flags survive a full pipe.
* CLI env specs: clear inherited `IYI_CACHE_DIR` when checking the Crystal
  fallback, and check that iyi's variable wins when both are set.
* Refuse integer `/` directly in interpolation or before `to_s`, naming
  `//` and `a.to_f / b`. Tape interpolation stays in ris.
* Concurrent builds of one entry share mutable object-cache paths: one can
  replace or remove another's objects before artifact assembly (std/http
  lost its TLS client unit in parallel gates; separate `IYI_CACHE_DIR`s
  pass). Make cache publication safe across builds in iyi.
* `String#byte_at(i)`: a bounds-checked byte read, beside `[]`.
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
  the client's delayed ACK (Nagle), 40 ms each (web, 2026-10-17). Take iyi's
  heap `String` overload; the tape one stays in ris.
* `IyiScheduler.current`: the running fiber inline, the first touch out of
  line. Two calls a `tape` made it 0.7% of respond (2026-10-18).
* `IyiScheduler.register`: a fiber list per thread, no runtime lock per
  spawn and end; a parallel task waits on a locked `@@pending` list until
  its worker moves it to its own (`started`). Per thread alone broke on
  0.19.1's steals: parallel_exercise crashed in a join, every second run.
* std/json: a string with an escape no longer makes a substring per
  non-ASCII run (`StringBuffer#append(Pointer, Int32)`), and the writer's
  escapes are `JSON.each_escaped_byte`. The lexer's span mode, the tape `Writer`
  and `Document` stay in ris.
* `IyiFloatText.write(bits, buffer)` / `format_into`: a float's text into
  a buffer, `to_s` on top. Keep bounded copies as fixed stores so LLVM 23
  does not introduce libc `memcpy` on Darwin after the extraction.
  `String::Builder#append_float` stays in ris.
* Both are iyi's branch `json-float-from-ris` (`c02af8fac`), not merged.
* `Pointer#unaligned_value`(`=`): an `align 1` access; `memcpy` copies
  words at any address on x86_64 and aarch64, its tail as one last word.
* Heap census, allocation stats and the `gc_none` trap; tape glue stays here.
## To make in iyi first
* Collections: `Array#includes?`/`index` and `Hash#fetch(key, default)`
  accept comparable lookup values without restricting them to stored types.
* std: `String#rchop`, `String#lchop(String)`; missing when a blog was
  written on web (2026-10-17).
* `String#[]` indexes bytes while `size` counts characters: at least say
  so in the docs and in a hint; a decision for iyi.
* `-Dgc_none` by default (`017ec91d3`): building `compiler_spec --release`
  passed 59GB, `Killed`. ris keeps bdw-gc; `gc_none=1` opts out.
* `editors/vim`: named arguments and keys (`user_id: x`, `{id: 1}`) as
  Ruby's symbols, `iyiNamedArgument`, with its tests.
* std/aead `seal_at`/`open_at` and std/tls records opened and sealed in
  place (`TlsRecordCipher#seal_at`, `#open_at`): no tape, nothing per record.
* CI differs from iyi's here, for a faster run (99 minutes was darwin's
  job): darwin's std foundation is a job of its own, the cursor sweep
  (`lsp_positions.py --shard K/N`) four shards, and the Linux and Windows
  std siblings eight; take to iyi, or keep apart when merging iyi.yml.
* Fixed lookup tables in time, cookies, DNS, MIME, system roots,
  compression, HPACK, JSON and TLS use static storage; `StaticArray#find`
  reads it without an Array copy.
* JSON lexer and token state are values. Span mode needs neither a string
  buffer nor a short-string cache, and no longer pools heap lexers.
* Socket accept and local-port queries use stack address buffers.
* TLS extension bytes are assembled into one sized array; fixed markers
  can be read directly from static storage.
* Time locations are immutable values; UTC stores its zone inline and
  needs no Location object or List backing arrays. A value identity keeps
  `local?` distinct from structural equality.
* Loggers allocate child tables only when used; context tables start
  empty. IOBackend writes the default format without a formatter object.
* Task launch validates ended state atomically with adoption; completed
  tasks stay live through tape cleanup before waking the group joiner.

## Stays in ris

* Tape: std/http `parse_head` and `ParsedHead`, the tape list in
  `RisRegion`, `AGENTS.md`'s tape rules.

* Generic macro reflection: preserve access to private types already bound
  as generic arguments when interpolation emits their canonical names.
  Keep unrelated private declarations behind the import/export wall.

## First-store collection inference

* Local empty arrays and hashes infer fixed types from their first store.
  The normalizer checks source order; deferred semantic type slots keep
  block parameters in scope. This is a ris language change to take to iyi.
* `Hash.new(default)` infers its key from the first index and answers a
  Hash(K, V) that carries its default (src/iyi/hash_tape.iyi).
  The inherited `src/iyi/` files and `.iyi` literal parsing stay unchanged.

## Suggested edits across lines

* `fix` splices the compiler's character span across source lines, so a
  suggested edit can replace an entire block while preserving later code.
  The text migration refusals stay in ris.
