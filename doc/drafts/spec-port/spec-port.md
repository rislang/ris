# Draft: port test/ to spec blocks

Status: draft, not reviewed. Needs an EGM review before any code or
SPEC.md change (AGENTS.md, CONTRIBUTING.md Design checks).

Context: spec blocks (doc/drafts/spec-blocks/spec-blocks.md, steps
1-8) are merged. A module file may end with `spec N.M ... end` blocks;
`ris test FILE` builds the module with its blocks; `ris check` runs
them and `ris check spec` ties them to SPEC.md through spec.lock. Its
step 8 removed `test "x" do` but left ris's own test/ in place: "a
port of ~1600 Crystal and program tests to spec blocks ... is left to
its own draft". This is that draft.

Its end state (step 8's gate) was "test/ holding only test/cli/ and
test/speed/". The inventory below shows that state cannot be reached
while the compiler is a Crystal program; section 6, Q1 asks the user
to amend it.

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
| ris           |   669 | RI   | 305 top, 316 refused, 13 other | splits |
| spec          |    24 | RI   | 24 todo stubs      | moves (todo)     |
| speed         |    26 | SH   | 12 py, 5 sh, 7 iyi | stays            |
| std           |   341 | CR   | 286 files, 9872 it | cannot move      |
| support       |    19 | CR   | helpers, no tests  | goes with CR     |

"it" counts lines starting `it ` or `test ` in .cr files.

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

They move only when the compiler is written in ris. Until then they
stay where they are and keep their make targets and CI jobs
(`std-test` in .github/workflows/ris.yml).

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
   becomes the Bool line `E`. Further candidates: the rest of the 84
   one-import programs (x509_parse, uri_tape, websocket_reader, ...),
   judged one by one in phase 3.
b. Program-level gates, stay: tests of the language and runtime
   (scope_*, task_*, board_*, heap_*, cleanup_*, side_*), tests that
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
compiler rule), the todo stays a test/cli entry (Q3).

### 2.4 test/cli and test/speed: stay

test/cli: 152 shell gates, 165 .iyi programs and fixtures; 111 are
`std_*_exercise.sh`, of which 110 call an outside oracle (openssl,
python3, curl, nc) or build `--release`. The oracle part stays a
gate; the in-process asserts in each `std_*.iyi` may move into the
module (phase 4). 142 scripts skip by platform (exit 77, uname).
test/speed: timings, never moved (AGENTS.md).

### 2.5 Totals

| group                               | count | end         |
|-------------------------------------|------:|-------------|
| Crystal `it` (compiler, std, ...)   | ~17030 | stays (CR) |
| test/ris module tests (a)           |    43 | spec blocks |
| test/ris other one-import (a?)      |    41 | judged      |
| test/ris program-level (b, d)       |  ~221 | test/cli    |
| test/ris refusals (c)               |   325 | test/cli    |
| test/spec stubs                     |    24 | todo blocks |
| test/cli std exercises, asserts     |   111 | split       |

## 3. Clauses

SPEC.md has chapters 1 (storage and lifetimes) to 7 (types, memory,
Ruby syntax): tape rules, not library behaviour.

| group                                   | clause            |
|-----------------------------------------|-------------------|
| tape do + copy_to(Program.tape) parts   | 1.1, 1.5, 1.9     |
| owners, growth (string_pool, deque)     | 2.1, 2.2          |
| roots (system, dns kept)                | 3.x               |
| task, board, socket parts (udp, sse)    | 5.1, 5.2          |
| heap refusals, pointer, ffi (refused/)  | 6.x, 7.x          |
| test/spec stubs                         | their own N.M     |
| RFC behaviour (base64 alphabet, json    | none              |
| grammar, toml, xz format, hpack, ...)   |                   |
| CLI tools of std (option_parser, shlex) | none              |

Most lines in the 43 module tests check what the format or RFC says,
which no clause covers. The spec-blocks rule (D1) is "a check that
proves no clause is a missing clause: write the clause first". Q2
asks how.

## 4. Proving no test is lost

- Ledger: test/cli/spec_port_ledger.txt, one line per old test:
  `test/ris/base64.ri -> src/std/base64.iyi spec 8.3 (7 lines)` or
  `-> stays test/cli/ris/...`. Written by phase 0 from the inventory
  above; each port edits its lines.
- Count gate: test/cli/spec_port_counts.sh counts, per old file, the
  `exit N unless` / `should` lines and, per ported module, the Bool
  lines in its spec section (`ris test --list`, or a grep of the
  section). A port must keep assertions >= the old count for that
  file, and every ledger line must name an existing file or block.
  Totals before/after are printed; a missing ledger target fails.
- Fails on purpose: for each module ported in the phase, the gate
  copies the module to test/cli/.work/, flips one Bool line (`==` to
  `!=`) and requires `ris test` to exit 1 naming that clause and
  line. A block that never runs (left out, wrong file) cannot pass.
- test/ris/check.sh: check_parallel.py's case list loses the ported
  programs and gains one `ris check test` run over src/std; its case
  count drops by exactly the ported files (ledger), which the gate
  checks.

## 5. Phases, smallest first

Each phase keeps `bash test/ris/check.sh`, the CI jobs in
.github/workflows/ris.yml and `ris check` green; each ends with its
gate green and `ris spec ack` for the reviewed clauses.

0. Ledger and counts. Write the ledger and spec_port_counts.sh; no
   test moves. Gate: spec_port_counts.sh passes on the current tree
   and fails when one ledger target is renamed. Add it to ris.yml.
1. Pilot: five small std modules (base32, base64, uuid, path,
   semantic_version). Each test/ris/<m>.ri becomes blocks at the end
   of src/std/<m>.iyi; tape parts name 1.1/1.5, format parts the
   clause from Q2. Gate: counts and the flip check for the five;
   `ris check test` runs them; check.sh green with five fewer cases.
   This phase also proves `ris check` over src/std itself (ris's own
   root) is fast enough to sit in check.sh: if not, see Q4.
2. The other 38 named module tests (a), in batches of about ten by
   area: text (csv ini toml json yaml xml regex shlex format
   number_format), net (dns secure_dns netip udp smtp mail sse
   websocket router query cookie mime fileserver autocert otp
   password), compression (bzip2 xz zip tar png hpack), rest. Tests
   that need a socket peer or a child process use spec-blocks 5.7's
   tmp and program handle; if one cannot, it stays (b). Gate per
   batch: as phase 1.
3. One-import programs (41 left of 84): each is moved to its module
   or marked "stays" in the ledger with a reason. Gate: no ledger
   line without a verdict.
4. test/cli std exercises: move each `std_*.iyi`'s in-process asserts
   into the module's blocks; the .sh keeps only the oracle and
   --release part. Gate: counts on the .iyi; each .sh still green.
5. test/spec stubs: each `todo` moves into the module that should
   keep N.M (Q3); the 24 files go. Gate: `ris check spec` reports the
   same todo set as before (diff of `ris spec` output).
6. Move what stays: test/ris/ to test/cli/ris/ (refused, forbid,
   warned, fix, the program gates, check.sh and its helpers), paths
   updated in ris.yml, Makefile, scripts and docs. Gate: check.sh
   green from its new path; `ris check` green; test/ holds cli/,
   speed/ and the Crystal suites of Q1.

Std leads (phases 1-4) because its tests are already module tests in
ris code. Phase 6 is a rename, kept last so the ports' diffs stay
readable.

## 6. Open decisions for the user

Q1. End state: the Crystal suites (~17030 `it`) cannot be spec
blocks.
  a. Amend step 8's end state: test/ holds cli/, speed/ and the
     Crystal suites until the compiler is in ris. (recommended)
  b. Move them under test/cli/crystal/ so test/ has two dirs.
  c. Drop test/std's tests of Crystal library parts the compiler
     does not use. Large audit; a separate draft.

Q2. Library behaviour fits no clause (RFC, format).
  a. One new clause, e.g. 8.1 "a std module keeps the standard its
     header names, byte for byte", named by every format block.
     (recommended: one SPEC change, honest, small)
  b. A SPEC chapter 8 with one clause per std area (text, net,
     compression, crypto): finer coverage, many clauses to review.
  c. Name the nearest tape clause (1.1) for all of it: no SPEC
     change, but `ris spec` overstates what 1.1 is proven by.

Q3. Where a test/spec stub's todo lives when no std module keeps
the clause (compiler rules, 6.x tooling).
  a. In a ris module under src/ris/ (e.g. src/ris/spec_todo.ri)
     that exists only for blocks. (recommended)
  b. Keep those stubs as files under test/cli/spec/.

Q4. How check.sh runs the moved blocks.
  a. One `ris check test` over the ris root (all src/std blocks),
     run in parallel by check_parallel.py per module. (recommended)
  b. A separate CI step `ris check test`; check.sh untouched.

Q5. Test programs that are named for a module but test the tape
(e.g. string_pool.ri, system.ri).
  a. Move them anyway and name 1.x/2.x clauses. (recommended)
  b. Keep them as program gates in test/cli/ris/.
