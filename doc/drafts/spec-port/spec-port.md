# Draft: port test/ to spec blocks

Status: reviewed 2026-11-11; decisions D1-D7 accepted.
Phases 0-2 are committed; phases 3-5 are implemented, uncommitted.
The final results and retained program-level reasons are below.

Context: spec blocks (doc/drafts/spec-blocks/spec-blocks.md, steps
1-8) are merged. A module file may end with `spec N.M ... end` blocks;
`ris test FILE` builds the module with its blocks; `ris check` runs
them and `ris check spec` ties them to SPEC.md through spec.lock. Its
step 8 removed `test "x" do` but left ris's own test/ in place: "a
port of ~1600 Crystal and program tests to spec blocks ... is left to
its own draft". This is that draft.

Its end state (step 8's gate) was "test/ holding only test/cli/ and
test/speed/". The inventory below shows that state cannot be reached
while the compiler is a Crystal program; D1 amends it.

## 0. Decisions (made by the user 2026-11-11; not reopened here)

D1. End state. test/ keeps cli/, speed/ and the Crystal suites
(compiler, compiler-cli, debug, llvm-ir, manual, primitives, std,
support) until the compiler is written in ris. spec-blocks.md's step
8 end state is amended to say so (phase 5 makes that edit).

D2. Library behaviour. One new SPEC clause: "a std module follows the
standard its header names" (number given when written, e.g. 8.1).
Every RFC or format check names it. It is a SPEC change: EGM review
and a SPEC_CHANGELOG entry before phase 1 uses it (section 3.1).

D3. Todo clauses no module keeps. A test/spec stub whose clause no
module keeps leaves no file and no module: the clause gets a todo
marker in SPEC.md itself, read by `ris spec` and `ris check spec`
(design in section 3.2).

D4. check.sh runs one `ris check test` over src/std, per module in
parallel (check_parallel.py gets one case per module with blocks).

D5. Tape tests named after a module (string_pool.ri, system.ri and
the like) stay program-level checks; they are not moved.

D6. The test/ris -> test/cli/ris move is dropped. test/ris stays.

D7. The 111 test/cli std_*.iyi asserts move only when their module
changes for another reason; they are outside this port.

## 1. Problem

- 43 programs in test/ris/ test one std module each (`base64.ri` tests
  `std/base64`) from outside: they see only exports, and an agent
  editing src/std/base64.iyi does not see them.
- A test names its clause only in a `# spec:` comment; 87 files carry
  one, most of test/ris/ carries none, so `ris spec` cannot say what
  the bulk of the suite proves.
- test/spec/ holds 24 placeholder programs (`clause_N_M_test.ri`),
  each only `todo "N.M untested: ..."`: a clause with no proof is
  tracked in a file far from any code.

## 2. Inventory (counts from grep, 2026-11-11, at fe9a5d0ee)

Form legend: CR = Crystal spec (`it`/`describe`, `*_test.cr`, run by
`make std_test` / `compiler_test` / `primitives_test`); RI = ris
program driven by test/ris/check.sh (check_parallel.py); SH = shell
or Python gate.

| dir           | files | form | tests              | verdict          |
|---------------|------:|------|--------------------|------------------|
| cli           |   549 | SH   | 152 .sh, 165 .iyi  | stays (gates)    |
| compiler      |   252 | CR   | 225 files, 7037 it | cannot move      |
| compiler-cli  |    20 | CR   | 10 files, 50 it    | cannot move      |
| debug         |    11 | CR   | 10 programs, sh    | cannot move      |
| llvm-ir       |    13 | CR   | 12 FileCheck, 16 it| cannot move      |
| manual        |    10 | CR   | 10 files, 17 it    | cannot move      |
| primitives    |     6 | CR   | 6 files, 38 it     | cannot move      |
| ris           |   669 | RI   | 305 top, 325 fail, 39 other | splits |
| spec          |    24 | RI   | 24 todo stubs      | moves (todo)     |
| speed         |    26 | SH   | 12 py, 5 sh, 7 iyi | stays            |
| std           |   341 | CR   | 286 files, 9872 it | cannot move      |
| support       |    19 | CR   | helpers, no tests  | goes with CR     |

"it" counts lines starting `it ` or `test ` in .cr files. test/ris's
325 "fail" are refused/ 316, forbid/ 2, warned/ 1, fix/ 6; its 39
"other" are the 20 .sh/.py helpers (2.2 d), expected-output files and
ris.mod files; each gets a ledger verdict only if it moves. test/cli's
549 files are 152 .sh, 165 .iyi and 232 fixtures and expected outputs.
Only `std-test` runs a Crystal suite in CI; compiler_test and
primitives_test run by make only.

### 2.1 Cannot move: the Crystal suites

test/compiler, compiler-cli, debug, llvm-ir, primitives, std, manual
and support test Crystal code: the compiler (src/compiler/) and the
Crystal library it is built with (101 `src/*.cr` plus src/<dir>/; not
src/std/, which is 121 `.iyi` files). A spec block is ris code inside
a ris module; it cannot call `Crystal::Parser` or `String#to_f` of
the host library. Samples: test/std/base64_test.cr tests Crystal's
`Base64` with `should eq`, not `std/base64`; test/llvm-ir/*.cr are
FileCheck inputs; test/debug drives lldb/gdb; test/manual needs the
network (badssl, https) or large files.

They move only when the compiler is written in ris (D1). Until then
they stay where they are with their make targets; this draft adds no
CI job for them.

### 2.2 test/ris: splits three ways

305 top-level programs. 169 import no std module (language and tape
rules: heap_*, scope_*, task_*, board_*, program_*, cleanup_*), 84
import exactly one, 52 import more than one; 140 open a `tape do`
block or use `Program.tape`; 116 have no `module` header.

a. Module tests, can become spec blocks: the 43 whose name is a
   src/std module (autocert base32 base64 bzip2 cookie csv debug deque
   dns eiy fileserver format hpack ini json mail mime netip
   number_format option_parser otp password path png query regex
   router secure_dns semantic_version shlex smtp sse string_pool
   system zip tar toml udp uuid websocket xml xz yaml). Sample
   base64.ri: `exit N unless Base64.decode(...) == raw` lines, one
   `tape do` with `copy_to(Program.tape)`; each `exit N unless E`
   becomes the Bool line `E`. Of the 43, string_pool and system test
   the tape, not the module, and stay (b) under D5; phase 2 checks
   the rest for the same and marks any such in the ledger. Further
   candidates: the rest of the 84
   one-import programs (x509_parse, uri_tape, websocket_reader, ...),
   judged one by one in phase 3.
b. Program-level gates, stay: tests of the language and runtime
   (scope_*, task_*, board_*, heap_*, cleanup_*, side_*), tape tests
   named after a module (string_pool.ri, system.ri; D5), tests that
   need a process (http_prefork, socket_race, signal_flags), and the
   respond sample checksum. No one module keeps their rule; a block
   in src/std/prelude would build the whole prelude per test.
c. Cannot move, must fail to build: refused/ (316 programs, each
   checked for its message and line), forbid/ (2 + ris.mod), warned/
   (1), fix/ (6 with .expected). A spec block's module must build, so
   a refusal can only be a program-level check (spec-blocks 5.7's
   `ris build` handle could drive one, but the 316 fixtures stay
   files either way).
d. Shell gates in test/ris/: 7 .sh (check.sh, board_checks,
   http_continue, ...) and 13 .py helpers: stay with (b).

### 2.3 test/spec: placeholders

24 `clause_N_M_test.ri` files, each a tag and a `todo`. Each becomes
`spec N.M` with the same `todo "reason"` in the module that should
keep the clause; the file is deleted. Where no module fits (a
compiler rule), the clause gets a SPEC.md todo marker (D3, 3.2).

### 2.4 test/cli and test/speed: stay

test/cli: 152 shell gates, 165 .iyi programs and fixtures; 111 are
`std_*_exercise.sh`, of which 110 call an outside oracle (openssl,
python3, curl, nc) or build `--release`. The oracle part stays a
gate; the in-process asserts in each `std_*.iyi` may move into the
module later (section 7). 142 scripts skip by platform (exit 77, uname).
test/speed: timings, never moved (AGENTS.md).

### 2.5 Totals

| group                                 |  count | end            |
|---------------------------------------|-------:|----------------|
| Crystal `it` (compiler, std, ...)     | ~17030 | stays (D1)     |
| test/ris module tests (a)             |     41 | spec blocks    |
| test/ris tape tests named for module  |      2 | stays (D5)     |
| test/ris other one-import (a?)        |     41 | judged (ph. 3) |
| test/ris program-level (b): 305-84    |    221 | stays test/ris |
| test/ris refused/forbid/warned/fix (c)|    325 | stays test/ris |
| test/ris helpers (d)                  |     20 | stays test/ris |
| test/spec stubs                       |     24 | blocks/markers |
| test/cli std exercises                |    111 | stay (sec. 7)  |

## 3. Clauses

SPEC.md has chapters 1 (storage and lifetimes) to 7 (types, memory,
Ruby syntax): tape rules, not library behaviour.

| group                                   | clause            |
|-----------------------------------------|-------------------|
| tape do + copy_to(Program.tape) parts   | 1.1, 1.5, 1.9     |
| owners, growth (string_pool, deque)     | 2.1, 2.2          |
| roots (dns parts; system stays, D5)                | 3.x               |
| task, board, socket parts (udp, sse)    | 5.1, 5.2          |
| heap refusals, pointer, ffi (refused/)  | 6.x, 7.x          |
| test/spec stubs                         | their own N.M     |
| RFC behaviour (base64 alphabet, json    | none              |
| grammar, toml, xz format, hpack, ...)   |                   |
| CLI tools of std (option_parser, shlex) | none              |

Most lines in the 43 module tests check what the format or RFC says,
which no clause covers. The spec-blocks rule (D1 there) is "a check
that proves no clause is a missing clause: write the clause first".
D2 adds that clause; 3.1 says how.

### 3.1 The standards clause (D2)

Text, for the EGM review of the SPEC change: "A std module follows the
standard its header names (an RFC, a file format, a published
grammar); its spec blocks check that standard's rules and examples."
The header names it in one comment line among the module's first
comment lines: `# standard: RFC 4648` (several allowed, one per
line). `ris check spec` refuses a `spec 8.1` block in a module with
no such line ("name the standard: add `# standard: ...` to the
header"); that check lands with the clause.

The clause goes in a new chapter 8, "Library", after chapter 7, as
8.1. It lands in its own commit at the start of phase 1, after the
EGM review of its text: SPEC.md, a dated SPEC_CHANGELOG entry naming
doc/drafts/spec-port/, the header check, the first pilot module's 8.1
blocks and `ris spec ack 8.1` together, so `ris check spec` never sees
8.1 uncovered. Tape lines in the same module still name 1.x/2.x.

### 3.2 The SPEC.md todo marker (D3)

Syntax: one line right after the clause's bullet text, indented two
spaces as its continuation lines, before any blank line:

    * 6.1 Pool(T)/SlicePool(T): typed slots/runs; ...
      <!-- todo: no test yet; needs a pool fixture -->

Regex `^  <!-- todo: (.+) -->$`, whole line at most 80 columns. An
HTML comment, so rendered SPEC.md shows nothing. A `<!-- todo:` line
anywhere else (after a blank line, unindented, two on one clause) is
an error of `ris check spec` naming the line, so a misplaced marker is
never folded into clause text silently.

Code sites in src/compiler/iyi/command/spec_clauses.cr (phase 4):

- Clause parsing (the continuation loop, lines ~157-208): a marker
  line is taken out before the text is hashed and kept as the
  clause's `todo` reason. Adding or removing it keeps the version, so
  it needs no lock update and is not a clause change.
- `spec_status`: a clause with a marker and no proof is `todo`, not
  `uncovered`; with a lock line it follows the lock as today.
- `spec_ack`: a marker counts as coverage, so `ris spec ack N.M`
  locks a marker-only clause.
- `spec_todo`: lists it as `SPEC.md:LINE N.M reason`; `ris spec N.M`
  prints `marker: SPEC.md:LINE`; JSON adds `"marker": "reason"`.
- The uncovered error of `ris check spec` skips marked clauses.

End: once a spec block or a tagged test (`# spec: N.M`) proves N.M
without `todo`, `ris check spec` fails: "SPEC.md:LINE: N.M is proven
by FILE:LINE; remove its todo marker". Prose mentions (`SPEC N.M` in a
comment) do not count. A marker beside a todo block for the same
clause also fails ("the block holds the todo; remove the marker"), so
a todo lives in one place. `--fix` does not edit SPEC.md.

Rules that change with it, in the same phase 4 change: spec-blocks
D2 and 5.14 ("todo lives only inside a spec block") and AGENTS.md's
spec paragraph gain "or as a SPEC.md marker for a clause no module
keeps"; AGENTS.md's "change SPEC.md only with a SPEC_CHANGELOG entry"
exempts marker lines; `ris spec --help` names the marker.

Gate (test/cli/spec_marker.sh): fixtures for a marked clause (todo,
ack works, hash unchanged), a marked and proven clause (fails), a
marker beside a todo block (fails), a misplaced marker (fails).

## 4. Proving no test is lost

A port gate for the port only; it is removed when phase 5 ends.

- Ledger: test/cli/spec_port_ledger.txt lists only files that move or
  are judged (the 41 module tests, the 41 one-import programs, the 24
  stubs, D5's two; actual union corrected in section 9). Each entry
  has a source line and indented JSON with its verdict, target, clauses
  and frozen old/new counts; a retained driver records its shell case.
  Phase 0 writes every verdict as `stays: todo`; each port edits its
  entry. Stub entries name their future module or marker target.
- What counts as an old assertion, per SRC: each `exit N unless`,
  `exit N if` and `raise ... unless` line, plus each check.sh line that
  checks that program's output (`want=`, `grep -q`, `[ "$out" = `,
  `RIS_HEAP_STATS`). New: the top-level Bool lines of the blocks that
  ledger line names, counted by grep between `spec` and `end` (no
  `ris test --list`; it does not exist). K new >= K old, per line.
- Output and heap checks: a check.sh case that compares stdout or
  requires "ris heap: 0 allocations" (path, mime, yaml, toml, xml, sse
  today) has no Bool form. The Bool lines move; the stdout or heap
  part stays a program-level check that builds the module with a
  small driver in test/ris/, and the ledger line says so. A port never
  drops such a check to make the count.
- Fails on purpose: per ported module, the gate copies it to
  test/cli/.work/ and, for every block, negates its first Bool line
  (wraps it as `!(E)`), one block at a time; `ris test` must exit 1
  naming that block's clause and line. A block with no Bool line is
  already refused (spec-blocks D13).
- check.sh: check_parallel.py loses one case per ported program and
  gains one `ris check test src/std/<m>.iyi` case per module with
  blocks (D4). The gate checks: old cases - ported + modules = new.
- Gate script: test/cli/spec_port_counts.sh; wired into ris.yml
  alongside the other CLI gates (heap shard), while the port lasts.

## 5. Phases, smallest first

Each phase keeps `bash test/ris/check.sh` (ris.yml and ris-macos.yml
run it), ris.yml's other jobs and `ris check` green; each ends with
its gate green and `ris spec ack` for the reviewed clauses. A batch
that cannot pass its gate is reverted whole; its ledger lines stay
`stays: todo` and the next batch goes on.

0. Ledger and counts. Write the ledger and spec_port_counts.sh; no
   test moves. Gate: it passes on the current tree and fails when a
   ledger target is renamed or a K new is below K old.
1. Standards clause, then pilot: 8.1 lands first (3.1). Then five
   small modules (base32, base64, uuid, path, semantic_version): each
   test/ris/<m>.ri becomes blocks at the end of src/std/<m>.iyi; tape
   lines name 1.1/1.5, format lines 8.1. path's stdout check stays as
   a driver (section 4). Gate: counts and flips for the five; check.sh
   case arithmetic; check.sh's wall time is printed before and after
   (report only; if it grows more than 20%, phase 2 waits for a fix).
2. The other 36 named module tests (43 less the pilot's five and D5's
   two), in batches by area: text (csv ini toml json yaml xml regex
   shlex format number_format), net (dns secure_dns netip udp smtp
   mail sse websocket router query cookie mime fileserver autocert
   otp password), compression (bzip2 xz zip tar png hpack), rest
   (debug deque eiy). A test needing a socket peer or child process
   uses spec-blocks 5.7's tmp and program handle; it stays only if
   that handle cannot express it, and the ledger names what is
   missing. Gate per batch: as phase 1.
3. One-import programs (41): a program moves only if its name or its
   one import makes the module obvious (x509_parse, uri_tape,
   websocket_reader, ...); the rest stay with `stays: program-level`.
   Gate: no ledger line left `stays: todo`.
4. test/spec stubs. Phase 0's ledger gives each of the 24 a target:
   a module, or `marker` for a compiler or tooling rule (1.x and 4.x
   rules of the compiler, 6.x tooling, 7.x types are expected to be
   markers; each is judged in phase 0, not here). Implement 3.2, move
   each todo, delete the files. Gate: spec_marker.sh; the set of
   clause numbers in `ris spec todo --json` is unchanged.
5. Close: amend spec-blocks.md's step 8 end state (D1); remove
   spec_port_counts.sh and the ledger. Gate: `ris check` green;
   `ris check spec` green.

Std leads because its tests are already module tests in ris code.

## 6. Open decisions for the user

None; D6 and D7 settle the last two scope choices.

## 7. Left out on purpose

- Moving test/ris/ to test/cli/ris/: under D1 test/ keeps several
  dirs anyway, so the move solves none of section 1's problems and
  touches ris.yml, ris-macos.yml, the Makefile and docs.
- The asserts in test/cli's 111 `std_*.iyi`: they already run, and
  section 1 does not list them. They move when their module is
  touched for another reason.
- Tagging the ~221 program-level tests that stay with `# spec:`: a
  separate pass; section 1's second problem is solved here only for
  the ported tests.

## 8. What the review changed

EGM review 2026-11-11 (design, implementation readiness, zoom-out,
comprehension, codebase details); no blockers left open.

- Readiness B: check.sh's stdout and zero-heap checks are counted and
  kept as program drivers (4).
- M: no `ris test --list`; one counting rule, per ledger line (4).
- M: flip negates one line in every block, `!(E)` (4).
- M: marker code sites, regex, ack of a marker-only clause, misplaced
  markers, and the rules it amends (spec-blocks D2, 5.14, AGENTS.md)
  are listed (3.2).
- M: phase 4 compares clause-number sets, not file paths; the 24
  stubs get targets in phase 0's ledger.
- M: 8.1's place, header syntax `# standard:`, and its one-commit
  landing with blocks and ack (3.1).
- M: check.sh case arithmetic made consistent (4, phase 1).
- M: only std-test runs a Crystal suite in CI (2.1); ris-macos.yml
  named.
- M (zoom-out): the test/ris move and the std_*.iyi split dropped
  (7); the ledger lists only files that move; the gate is temporary.
- Minors fixed: 8.3 to 8.1, totals that add up, "rest" batch listed,
  timing threshold, rollback rule, one-import criterion, D5 in 3.

Minors left:
- Define "spec section", `ris check test`, `ris spec ack` here: they
  are spec-blocks.md's terms; this draft cites that one.
- Trim the marker's JSON and `ris spec N.M` output (zoom-out 5): kept;
  they are a few lines and keep the marker visible as a todo block is.
- Tagging the stay-behind tests (zoom-out 6): section 7.

## 9. Implementation notes (2026-11-11, phases 0-1)

- Ledger entries use a source line and indented JSON metadata, keeping
  document lines within 80 columns. Frozen old counts are recorded before
  moving anything; stays entries are recounted on every gate run.
- Count `exit N if` too: base32 uses it for a decode error. Omitting it
  would silently lose an assertion.
- check_parallel.py groups shell loops as cases, not individual programs.
  Case arithmetic therefore counts its actual blocks; retained stdout
  and heap drivers keep their existing loop case. Each pilot gains its
  own module case. All four existing pilot drivers keep their heap and
  PASS checks, not only path. base64 had no check.sh case.
- Nested tape Bool expressions are not spec assertions (spec-blocks
  5.2). Format checks are at block top level; separate 1.5 blocks check
  copied values after the tape closes. The gate scans statement starts
  at two-space indentation and flips complete multiline expressions.
- Phase 0 assigns all stub targets; marker implementation and stub
  deletion remain phase 4. No SPEC todo marker is introduced in 0-1.
- Full check.sh timing is deferred: this task explicitly runs only pilot
  cases. Selected-case wall times are reported, with no full-suite claim.
- Inventory correction: the 84 single-std-import programs overlap only
  30 of the 43 named programs; their union is 97, plus 24 stubs gives
  121 ledger entries. The gate records the actual union, not 108.
- Pool stubs also target markers: there is no std/pool module in this
  tree; these rules are implemented by the compiler/runtime.
- Computed top-level base32/base64 tables made those libraries look like
  programs to the test runner, which dropped the tables. Tables now live
  inside the types using them; initialization and algorithms stay intact.
- Pilot path exposed a test-infrastructure import cycle:
  path -> ris_spec -> dir -> path. Pure Bool proofs now omit the unused
  process/tmp helper import; blocks using tmp, free_port, program handles
  or their types keep it. A regression case in spec_blocks_run.sh failed
  before the compiler fix. This preserves the available spec vocabulary.
- Each retained pilot loop has three shell checks (heap-stats request,
  PASS grep, zero-heap grep). Old/new totals include those three; the
  gate hashes the retained shell case so a dropped output or heap check
  fails rather than being hidden by extra Bool assertions.
- Path also exposed declaration detection omitting impl and conditional
  declarations. The detector now keeps impl and macro branches made only
  of declarations, rather than misclassifying the module as a program.
- Stays entries freeze program and shell counts separately (`old` and
  `shell_old`); ported entries combine old checks and count retained shell
  checks alongside new Bool lines. Quoted string contents are ignored by
  the Bool-line scan (base32 padding contains `==` but is not an operator).
- Negative probes: deleting one base32 Bool line gives
  `FAIL: spec port counts: test/ris/base32.ri: 12 new < 13 old`; renaming
  its destination gives `missing target`. Both probes restore the source.
- Flip copies keep the `std/<module>.iyi` suffix beneath .work. The
  compiler derives a module root from its header/path agreement; a flat
  copy of path.iyi was not an equivalent build and failed before testing.
- Final pilot totals (including retained shell checks): base32 13 -> 13,
  base64 7 -> 7, path 19 -> 19, semantic_version 18 -> 18, uuid 14 -> 14.
  Format assertions name 8.1; retained copies are checked under 1.5.

Verification at the phase 1 stopping point:

- Phase 0: `PASS: spec port counts (0 modules, 0 flips)`; 485 cases.
- Phase 1: `PASS: spec port counts (5 modules, 10 flips)`;
  `485 old - 0 removed + 5 modules = 490 new`.
- Deliberately dropped Bool: `12 new < 13 old`, exit 1; restored.
- All seven spec_blocks_*.sh gates pass; spec_verb.py: 52 steps passed.
- `bin/ris check spec`: 43 clauses, 19 ok, 24 todo, 0 to review,
  0 uncovered, 0 unversioned. Clauses 1.5 and 8.1 acknowledged.
- Actual check.sh selection: `PASS: selected ris checks`; only pilot
  cases and their existing grouped driver cases ran.
- Pilot-only selected-case wall time: 4.83s before, 5.79s after. This
  excludes unrelated cases and is not the full-suite 20% timing gate.
- LLVM 23.1.3 build and changed Crystal files' formatting check pass.
- No commit; marker support/stub deletion and later ports remain phase 4
  and phases 2-5 respectively. Own .work scratch is removed.

## 10. Phase 2 batch results (2026-11-11)

Phase 2 was attempted with the whole-batch rollback rule in section 5.
Only deque and eiy remain ported. No compiler or library algorithm was
changed to force a batch through the gate. Failed batches keep their
original programs, shell cases and `stays: todo` ledger entries.

- Text: rolled back all ten listed modules. CSV's stream reader refuses
  a live view of CSVReader.@bytes in the module proof. TOML and YAML
  cannot resolve their own derive macros in the module's test build.
  JSON's computed POW10 is dropped as program initialization. The gate
  failed on CSV; selected module cases also exposed the other failures.
- Net: rolled back the whole batch. After adapting nullable assertions,
  separate owner declarations and String locals, Cookie.parse still
  refuses its loop-local lowercased domain escaping the round. The
  mutation gate fails to build cookie, so passing router, websocket,
  mime and sse cases are not kept on their own.
- Compression: rolled back all six modules. HPACK's computed
  HUFFMAN_CODES is dropped as program initialization; ZIP's default
  modification time reaches Time.read_local, whose result is refused
  under SPEC 1.9. The gate also mistakes HPACK's loop for a Bool line
  because its indented body contains comparisons; the mutation is a
  syntax error, not the required BROKEN result. None of these failures
  is accepted as a successful flip.
- Rest: deque and eiy pass. All seven original eiy assertions move;
  deque gains direct assertions for its printed operations. Their
  original output/heap shell cases remain byte-for-byte unchanged.
  eiy keeps a small allocation driver; deque keeps its output driver.
  debug stays program-level for the handle limitation below.

Corrections to the draft's assumptions:

- Phase 2's area lists total 35, not 36: option_parser is missing.
  It belongs in the text batch and remains unported with that rejected
  batch. The phase still has 36 candidates, of which 34 remain.
- Section 5 overstates the process vocabulary. RisProgram runs only the
  plain program-under-test via RIS_SPEC_PROGRAM. A library spec block
  has no `ris build` source handle to compile and run an arbitrary
  fixture. debug needs that separate panicking process; its ledger
  records the missing handle. tmp alone cannot supply that capability.
  Adding a general build handle is outside this test-port phase.
- Output-comparing drivers need not print a PASS sentinel: deque prints
  its operation results. The port gate no longer requires that literal;
  it still requires the driver file and the exact retained shell-case
  hash, so its output and zero-heap checks cannot disappear silently.
- Repeated assignments to an owner cannot be flattened into one spec
  scope. The net attempt used a separate EventParser declaration for
  the second SSE stream. Append-only String.build forms also need
  String locals in module proofs; this alone did not require changing
  library APIs or compiler behavior.

Verification of the retained phase 2 result:

- Before: `PASS: spec port counts (5 modules, 10 flips)`;
  `485 old - 0 removed + 5 modules = 490 new`.
- After: `PASS: spec port counts (7 modules, 12 flips)`;
  `485 old - 0 removed + 7 modules = 492 new`.
- Counts including retained shell checks: deque 3 -> 18, eiy 10 -> 10.
- The failed text, net and compression batches remain fully reverted.
  Their failures are recorded above, not reported as green ports.
- No full check.sh or full-suite timing claim: only module cases and
  the retained drivers are selected, as requested for this task.

- LLVM 23.1.3 build passes. All seven spec_blocks_*.sh gates pass;
  spec_verb.py reports `52 steps passed`.
- `bin/ris check spec`: 43 clauses, 19 ok, 24 todo, 0 to review,
  0 uncovered, 0 unversioned. Clause 8.1 acknowledged after review.
- Retained module and driver selection: `PASS: selected ris checks`.
  The full check.sh and the full suite were not run.

- The broader phase 2 selection also passes: 33 check.sh cases,
  including the original drivers of the rejected batches and their
  grouped loops, end with `PASS: selected ris checks`.
- No commit was made. Own scripts, compiler cache and temporary files
  under test/cli/.work/ were removed; existing scratch was preserved.

### 10.1 Retry after spec-build repairs (2026-11-11)

The three regressions have small checks in spec_blocks_run.sh. On the
phase 2 binary, the computed-table check failed with the dropped-name
error, the local derive failed as unavailable, and the loop scanner
returned both the loop and its following Bool instead of only the Bool.
A second derive probe, using a trait, exposed a missing TraitDef in the
declaration list. Both derive forms now pass.

- Computed constants are declarations regardless of their initializer.
  Test builds retain their initialization, including JSON's POW10 and
  HPACK's HUFFMAN_CODES. Program statements are still omitted.
- Trait declarations stay too. Macro lookup walks enclosing namespaces,
  so nested test types can derive with macros in their own entry module.
  The program gate also checks a computed constant beside program code.
- Port counting inspects top-level statements, skipping control blocks,
  raises and output effects. Multiline Bool expressions still count as
  one check. Mutation preserves continuation newlines and their backslashes.
  A nested comparison can no longer turn a loop into a syntax-error flip.

Thirty additional modules have blocks. Text: csv, ini, toml, json, yaml,
xml, regex, shlex, format, number_format and option_parser. Net: dns,
netip, udp, smtp, mail, sse, websocket, router, query, mime, fileserver,
otp and password. Compression: bzip2, xz, zip, tar, png and hpack.
Together with the seven retained ports, that is 37 modules.

The existing output, heap and integration drivers stay byte-for-byte
unchanged and their shell cases are pinned in the ledger. They retain
large codec corpora, socket exchanges and printed-format comparisons.
number_format and router have no retained shell case and their programs
are removed. JSON keeps its heap_trap driver; that shorthand is now
explicitly recorded as its retained case. No library API was changed.

Lifetime adaptations and retained program checks:

- CSV's blocks use the callback parser and copy retained rows to their
  owner. The original stream-reader/output driver remains: a module
  proof must not retain a live view across CSVReader.@bytes refill.
- Cookie remains program-level. Even a minimal Cookie.parse proof with
  Domain=.EXAMPLE.COM refuses the loop-local lowercased domain escaping
  its round (SPEC 1.1, 3.6). The compiler rule and library API stay.
- ZIP passes with an explicit Time.unix modification time. Its proof does
  not invoke the Time.read_local default refused under SPEC 1.9.
- TAR reads the current entry before advancing; it retains no entry view
  across the reader's next names-buffer clear.
- secure_dns remains program-level: its Python TLS/HTTPS peer generates
  the CA and port files and takes a fixture directory argument.
- autocert remains program-level: autocert_checks.py builds its separate
  program, generates short-lived PEM identities and runs the lifecycle
  fixture. RisProgram cannot build/run an arbitrary fixture or start the
  Python fixture generator; it runs only the plain module under proof.
  debug's previously recorded process-handle limitation is unchanged.

The TLS/PKI fixtures are not a reason to roll back independent module
proofs. Their original programs and shell checks remain, with explicit
program-level ledger verdicts. No later port phase was attempted.

Verification of this retry:

- The new probes were red before the compiler/scanner fixes: computed
  constant dropped; own derive unavailable; loop checks [(1, 3), (4, 5)]
  instead of [(4, 5)]. The trait form also failed before TraitDef stayed.
- After: spec_blocks_run reports `PASS: spec blocks run`; the changed
  program fixture reports `spec_blocks_program: ok`. All seven
  spec_blocks_*.sh gates pass.
- Baseline from the committed phase 2 record above:
  `PASS: spec port counts (7 modules, 12 flips)`; 492 shell cases.
- Retry: `PASS: spec port counts (37 modules, 42 flips)`;
  `485 old - 0 removed + 37 modules = 522 new`.
- `spec_verb: 52 steps passed`; `bin/ris check spec` reports
  `43 clauses: 19 ok, 24 todo, 0 to review, 0 uncovered, 0 unversioned`.
- The 30 added module runs pass. Selected check.sh module and retained
  driver cases report `PASS: selected ris checks`, including the pilot,
  deque and eiy driver loops. No full check.sh or full suite was run.
- LLVM 23.1.3 build passes. No commit is made; the lead reviews and
  commits. Own .work scratch is removed at the stopping point.

Additional compiler verification:

- iyi_derive_test.cr: `14 examples, 0 failures, 3 errors, 0 pending`.
  Unchanged HEAD produces the same three errors at lines 96, 178 and
  527: two old fixtures omit OnTape, and one still uses String.view.
  No inherited test was changed to hide those failures.
- Crystal formatting was checked. parser.cr passes; call.cr has existing
  formatting differences outside the added hunk. The unchanged HEAD
  copy also fails its formatting check. Unrelated reformatting is left
  to a separate change. `git diff --check` passes.

## 11. Phase 3 results (2026-11-11)

Nine more programs contribute proofs in seven modules: big_tape to
big, std_text_tape to text, std_io_tape to io, dir_children to dir,
time_tape_offset to time, tls_error_message to tls, and uri_legacy,
uri_tape and params_write_tape to uri. Their existing shell cases and
program drivers remain unchanged for output and heap checks. No library
API changed. The actual one-import union has 56 unjudged entries, not
the estimate of 41; all now have a verdict. Nine contribute proofs and
47 stay program-level; with the four earlier holdouts, 51 remain. The
final total is 46 proof sources in 44 modules.

Program-level reasons (including the four phase 2 holdouts):

- allowed.ri: Compiler owner alias, constructor and scope acceptance; int is
  incidental.
- autocert.ri: Python-generated PEM fixtures and a separate lifecycle program.
- autocert_wire.ri: Board handoff, deep copies and bounded order integration.
- cleanup_allocations.ri, cleanup_cancel.ri, cleanup_current.ri,
  cleanup_exit.ri, cleanup_order.ri, cleanup_self.ri, escape.ri,
  heap_exemptions.ri, heap_kinds.ri, hpke_owners.ri, json_buffer.ri,
  lifetime_flow.ri, little_endian.ri, local.ri, local_cleanup.ri, log_tape.ri,
  query_scope.ri, round_struct_kept.ri, scope_cleanup.ri, slice_dup.ri,
  socket_kept.ri, static_array_copy.ri, string_parameters.ri, string_pool.ri,
  svcb_store.ri, system.ri, tape_string.ri, task_reached_proc.ri,
  text_format_tape.ri, thread_program_initializers.ri, toml_round_flags.ri,
  zero_capacity.ri: Tape lifetime, retention or cleanup rule; import supplies
  its fixture.
- const_int_width.ri: Compiler constant folding regression, not std/int
  behavior.
- cookie.ri: Cookie.parse retains loop-local domain (SPEC 1.1).
- debug.ri: Panic/backtrace requires a separate program. Library blocks have
  no source-build handle for a fixture. RisProgram only runs the
  RIS_SPEC_PROGRAM binary.
- file_metadata.ri: Argument-selected stat failures and symlink fixture;
  separate process statuses.
- iterator_stop.ri: Compiler value return and union dispatch for Stop.
- log_async.ri: Task/board lifecycle and asynchronous backend integration.
- log_for_constant.ri: Program-rooted logger constants and initialization
  lifetime.
- once_in_program_init.ri: Program initialization and once storage lifetime.
- option_parser_panics.ri: Six separate panic processes selected by program
  arguments.
- pipe_reuse.ri: Pipe handle reuse and task handoff integration.
- pipe_wait.ri: Pipe parking, concurrent tasks and scheduler integration.
- secure_dns.ri: External Python TLS/HTTPS peer and certificate fixture.
- signal_flags.ri: Process signal delivery and flags.
- socket_pair.ri: Connected socket/task integration and zero-heap driver.
- socket_pieces.ri: Loopback peer, parked writes and task ownership
  integration.
- xpath.ri: Printed XPath selections compared with external Python oracle.

Adaptations and compiler regression:

- big uses an append-only String local instead of String.build, following
  the compiler refusal. URI keeps the normalized value in a separate
  local. No library API or lifetime rule was relaxed.
- URI's invalid-input and resolution loops accumulate a Bool checked at
  block level; time's three input cases each have their own block.
- io exposed a nested conditional declaration being dropped. The new
  conditional.ri probe in spec_blocks_run.sh failed before the fix with
  undefined Value.new. The parser now checks complete macro alternatives,
  preserving class/module text surrounding nested branches. It still
  rejects program statements as declarations. io and dir then both pass.
- Multiple ledger sources can share a destination; case arithmetic and
  mutations count each module once. Assertions still count per source.

Verification:

- Before: `PASS: spec port counts (37 modules, 42 flips)`;
  `485 old - 0 removed + 37 modules = 522 new`.
- After: `PASS: spec port counts (44 modules, 53 flips)`;
  `485 old - 0 removed + 44 modules = 529 new`.
- All nine source programs' retained shell cases (including grouped
  loops) and seven module cases: `PASS: selected ris checks`.
- Seven spec_blocks gates pass; `spec_verb: 52 steps passed`.
- `bin/ris check spec`: 43 clauses, 19 ok, 24 todo, 0 to review,
  0 uncovered, 0 unversioned. Clause 8.1 reviewed and acknowledged.

## 12. Phase 4 results (2026-11-11)

All 24 phase-0 stub targets are markers: compiler and built-in runtime
rules have no standalone std module. Every test/spec file is removed;
SPEC.md now carries one todo marker beside each of those clauses. No
stub remains, and no placeholder module was invented.

The old reasons were unfinished clause excerpts. Marker reasons retain
that untested intent as short, complete descriptions within 80 columns;
the repeated clause number is provided by the containing clause. This
changes no clause text or hash and requires no spec.lock update. The
marker-only exception is recorded in AGENTS.md; this is not a semantic
SPEC edit and adds no SPEC_CHANGELOG entry.

- Before implementation, spec_marker.sh fails: the marked clause is
  `uncovered`, and its comment changes the hash to 4a6bb4fe.
- After: `PASS: spec marker`. Fixtures cover todo status, ack, unchanged
  hashes across insertion/removal/reason edits, stale locks, proof and
  todo conflicts, prose mentions, malformed/misplaced/duplicate markers,
  the 80-column limit, JSON/text reports and --fix leaving SPEC.md alone.
- `PASS: todo clause set unchanged (24 clauses)` before/after migration.
- `PASS: SPEC text unchanged apart from 24 marker lines`;
  `PASS: all 43 clause hashes still match spec.lock`.
- Final port gate: `PASS: spec port counts (44 modules, 53 flips)`;
  `485 old - 0 removed + 44 modules = 529 new`.
- All seven spec_blocks gates pass; `spec_verb: 52 steps passed`.
- `bin/ris check spec`: 43 clauses, 19 ok, 24 todo, 0 to review,
  0 uncovered, 0 unversioned. Tagged files fall from 87 to 63.
- All moved programs' retained cases and the seven added module cases:
  `PASS: selected ris checks` after final formatting and marker support.

## 13. Phase 5 close (2026-11-11)

- spec-blocks step 8 now names the D1/D6 end state: cli/, speed/, ris/
  and the Crystal suites remain. The host compiler/library suites cannot
  become ris blocks until the compiler is written in ris. The existing
  111 std exercise gates stay under D7.
- Removed spec_port_counts.sh, spec_port_counts.py and their ledger,
  after their final green gate. Removed the scanner-only probe coupled
  to that temporary helper; the compiler regression probes remain.
- CI replaces the temporary port job with the permanent spec_marker.sh
  gate. No workflow names the removed scripts.
- spec-blocks D2 and 5.14, AGENTS.md and `ris spec --help` describe
  markers; UPSTREAM.md records both compiler/tooling changes for iyi.
- The requested scope uses a targeted `ris check` over the seven changed
  modules plus root `ris check spec`, never the full suite or check.sh.
  The targeted check passes format, types, unused and test, ending
  `ok in 14.7s` after closure (16.4s before). Formatter-only changes are
  kept in the touched modules so that this gate is green. No library API
  or algorithm changed.
- No commit is made; the lead reviews and commits. Own .work files are
  removed at completion; earlier agents' scratch remains untouched.

Final diagnostic review found one more regression in the marker code:
with multiple tag lines, the conflict pointed to the first tag rather
than the line naming the marked clause. The added marker probe failed
with test/proof.ri:1 instead of :2 before the fix. Tag locations are now
stored per clause, not just per file.

Final verification after that diagnostic fix: `PASS: spec marker`, all
seven spec_blocks gates pass, `spec_verb: 52 steps passed`, and root
`ris check spec` still reports 43 clauses, 19 ok, 24 todo, 0 to review,
0 uncovered and 0 unversioned. The seven-module `ris check` ends
`ok in 16.2s`. Own scratch was removed; no commit was made.
