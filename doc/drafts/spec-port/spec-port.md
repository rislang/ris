# Draft: port test/ to spec blocks

Status: draft, decisions D1-D5 in. Needs an EGM review before any
code or SPEC.md change (AGENTS.md, CONTRIBUTING.md Design checks).

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

Code sites in src/compiler/iyi/command/spec_clauses.cr (phase 5):

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

Rules that change with it, in the same phase 5 commit: spec-blocks
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
  stubs, D5's two). One line each:
  `SRC -> DEST spec N.M (K old, K new)` or `SRC -> stays: reason`.
  Phase 0 writes it with every verdict `stays: todo`; each port edits
  its lines.
- What counts as an old assertion, per SRC: each `exit N unless` and
  `raise ... unless` line in the program, plus each check.sh line that
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
- Gate script: test/cli/spec_port_counts.sh; run by `ris check`'s
  cli part while the port lasts, not added to CI as its own job.

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

None from D1-D5; the review raised two scope choices, listed in the
report to the lead.

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
