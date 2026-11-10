# Draft: test blocks in module files

Status: amended after EGM review
([consolidated_review_report.md](consolidated_review_report.md));
section 9 says what changed. No compiler code yet.

Context: ris is iyi plus Goose's tape memory (AGENTS.md). Today a test
is a whole program, `*_test.ri`, that exits 0 to pass, 77 for todo
(iyi SPEC's `go test` row: "every `*_test.iyi` is a program"). Inside
one, `test "name" do ... end` (src/iyi/testing.iyi) runs a named case
as a task of its own, so a failing case ends only itself. `ris spec`
ties SPEC clauses to tests by a `# spec: N.M@VERSION` tag in a test
file's leading comment block (doc/drafts/spec-cli/spec-cli.md). The
model for this draft is Koja's `test` declaration
(doc/reference/koja/design/TESTING.md).

A module file starts with a `module PATH` header line, not a
`module ... end` body (init.cr:161); everything below it is the
module's top level.

## 1. Problem

A unit test of a module's private def cannot be written: a test
program sees only what the module exports. So an agent either makes the
def public to test it, or tests it only through the whole program, and
a failure points at the program, not the def. The test also lives far
from the code it checks, so an agent changing `Store.slugify` does not
see its tests.

## 2. Decisions (made by the user; not reopened here)

D1. A module file may end with test blocks, Koja-style:

    test "a title becomes a slug"
      assert Store.slugify("Tere <b> öö") == "tere-b"
    end

Tests go at the end of the file, after the code. (The compiler enforces
it: 4.2.)

D2. `ris build` and `ris run` leave test blocks out: nothing of them is
in the binary. `ris test` builds each module that has test blocks into
one test program (Go's one binary per package) and runs it; a failing
block is reported by file:line and its description.

D3. A spec tag may sit on a test block: a `# spec: N.M@VERSION` comment
directly above `test`. `ris spec` and `ris check spec` read it; a
tagged block counts as one test, as a tagged file under test/ does
today.

D4. Program-level tests (start the program, send a request) stay
programs under test/, with a `module test/<name>` header so imports
resolve from the project root (iyi rule R-1, iyi SPEC "module paths
are absolute, resolved from the project root"; this works today).

## 3. Goals and non-goals

Goals: a def is tested next to it, private defs included; a release
binary carries no test; `ris test` and `ris spec` walk the same files;
a failure names file:line and the block.

Non-goals: no new assertion library (`assert`, `assert_eq` and the rest
of testing.iyi stay); no suites or nesting (`describe`); no change to
program-level tests; no result cache, no LSP run action and no new
`--affected` rule (section 8).

## 4. Design

### 4.1 Grammar

A test block is a top-level declaration of exactly this shape:

    test STRING NEWLINE
      statements
    end

- STRING is a plain string literal (no interpolation), so tools read
  the description without running anything.
- `test` at the start of a top-level line is reserved for this form.
  Any other shape there is an error naming the fix: `test "x" do` and
  `test("x") { }` ("a named case belongs in a test program under
  test/; at the end of a module write `test \"x\"` then the body and
  `end`"), `test "x", opt`, `test("x")`, `test` with no literal.
  `def test(...)` at top level is refused too ("`test` starts a test
  block; name the def otherwise"). Inside a def, a block or a test
  program, `test` stays testing.iyi's call, as today.
- In a `*_test.ri` program the declaration form is refused: "a test
  program uses `test \"x\" do ... end`; a test block belongs at the
  end of the module it tests". One form per place.
- The body is statements; no parameters, no result. `assert` and the
  testing.iyi assertions work as in a test program: a failure is a
  panic carrying file:line.
- Two blocks in one file may not share a description: refused, naming
  both lines. The description is the block's key (4.7).

### 4.2 Place: the test section

The first test block starts the file's test section; it runs to the
end of the file. The section may hold only test blocks, `import` lines
(test-only, 4.4) and `private def` helpers.

The compiler enforces it, not only the formatter or AGENTS.md
(AGENTS.md: "a rule lives in the compiler"). Anything else after the
first block is refused with the fix: "`def render` comes after the
test block at store.ri:40; move it above the first `test`: tests go at
the end of the file". The formatter does not reorder code.

A helper may not share a name with a def above the section ("the
helper `slugify` would replace the code under test; rename it"), so a
helper never overloads or shadows the code it tests. Code above the
section cannot call a helper: in a build the section does not exist.

A file with top-level statements (code that runs, like init's
`puts "hello from demo"`) may not have test blocks: "store.ri runs
code at its top level; move it into a def, or test it as a program
under test/". So a test program never runs a module's own code, and an
entry file is tested as a program (D4).

### 4.3 What a block sees

A block is compiled in the module's top-level scope, as a private def
of the module would be: it sees private defs, private types and
constants (Koja: a member test reaches `priv` members), and may call
them qualified (`Store.slugify`, as in D1) or not. It sees the
module's normal imports, its test-only imports and its helpers.
Nothing outside the file sees a block or a helper.

### 4.4 Test-only imports

A harness or std/dir needed only by the tests must not enter the
module's build; Koja links its Test package only when tests load.

Recommendation: an `import` in the test section is test-only. `ris
build`, `ris run` and `ris doc` drop the whole section, imports
included, before name resolution: they are not in the module's import
DAG, its export metadata (R-1: a module is compiled against its
imports' metadata, never their bodies) or the binary. An import above
the first block is a normal import, as today.

Considered: a `test import` form (clear at the line, but new syntax
that could sit anywhere); an `@[TestOnly]` mark (an annotation with a
file-wide effect). The position rule needs no new syntax and reuses
4.2's boundary.

A test-only import of a module that imports this one is refused: "the
test of store imports web, which imports store; test store through web
as a program under test/". Allowing it buys nothing shown today and
would need a second compile of the module; lift it if a need appears.

`ris build` does not type-check test sections; `ris check types` and
`ris test` do, so an agent's `ris check` still catches a broken block.

### 4.5 The test program

For each module M with blocks, `ris test` builds one program: M with
its test section, every other module without one, and a generated
`main` that runs each block in file order as a named case (task per
case, as testing.iyi does: a failing block ends only that block).

Runtime change: `todo "reason"` in a block ends only that block and
records it as todo in IyiTestCases (today `todo` calls `exit 77` and
would end the whole program). The program's verdict: 1 if any block
failed, else 77 if any was todo, else 0. On wasm32, where there are no
tasks, the first failure or todo ends the program, as named cases do
today; step 4's gate builds one wasm32 case to show it.

Output, one line per block, after the panic's evidence for a failure:

    ok - src/store.ri:42 a title becomes a slug
    FAIL - src/store.ri:48 an empty title is refused
    TODO - src/store.ri:55 umlauts keep their letter: needs a table

Paths are relative to ROOT. `ris test` sums the programs it ran, as it
sums test programs today: `3 programs, 12 blocks: 10 ok, 1 failed,
1 todo`. `ris test src/store.ri` runs that module's blocks (today any
file argument is taken as a program, test.cr:110-112).

Tape: each block is a def body, so it frees its temporaries when it
ends (SPEC 1.1); nothing new is needed.

### 4.6 One walk for `ris test` and `ris spec`

One function walks the project and returns two lists:

- programs: `*_test.ri` / `*_test.iyi` under `ROOT/test/`;
- modules with blocks: `.ri` / `.iyi` files anywhere under ROOT whose
  parse holds a test section (a cheap scan for a line starting
  `test "` picks the candidates; the parse decides, so a heredoc or a
  `test "x" do` call does not count).

It leaves out `lib/`, `mods/`, every directory whose name starts with
a dot, and fixture trees: a directory holding a `.ris-fixtures` marker
file (test/cli/ fixtures with failing blocks are run by their gate,
not by the project's `ris test`). ROOT is the nearest directory up
holding `ris.mod` or `iyi.mod` (spec-cli 4.1).

`ris test` builds programs and modules with blocks. `ris spec` reads
tags from both lists plus its other files under test/ (`.cr`, `.sh`,
`.py`, spec-cli 4.3). The per-verb filter is the only difference.

Bugs this fixes:

- B1. `ris test` with no path walks `.` (test.cr:92) with
  `**/*_test.ri` (test.cr:107-109), so it runs tests under lib/,
  which belong to another project. Fixed in step 1, before blocks.
- B2. `ris spec` reads only test/, so a tag on a block in src/ would
  be missed. Fixed in step 5, with tags on blocks.

### 4.7 Spec tags on blocks

`# spec: N.M@VERSION` lines (or `# spec: none (reason)`) directly
above `test`, with no blank line between, tag that block. Its key is
`file + description`, so an edit above the block does not move it;
reports show `file:line "description"`. A module file has no whole-
file tag: a tag in its leading comment block is refused ("this file is
a module, not a test; put the tag directly above a `test` block").

`ris spec ack N.M` rewrites the version in existing block tags, as it
does in file tags; it never inserts a tag. A block tag is stale like a
file tag: its version differs from the clause's. Reports list a block
where they list a file:

    1.3   to review   2  test/http_test.ri
                         src/store.ri:42 "a title becomes a slug"

A todo block covers its clause as a todo program does.

### 4.8 `ris init` (separate fix, step 2)

`ris init demo` writes test/demo_test.ri with no `module` line, so the
first `import demo` added to it fails: without a header the root is
the file's directory, test/. Init writes the tag first, the header
below it, so the tag stays in the leading comment block:

    # spec: 1.1@VERSION
    module test/demo_test

    todo "run demo.ri and check that it prints `hello from demo`"

The "can't find module" error, when the importing file has no `module`
header and sits below the project root, adds: "add `module
test/demo_test` as its first code line so imports resolve from the
project root".

### 4.9 Tools

- Formatter: formats blocks like defs; keeps them where they are.
  Gate in step 3: `ris format` leaves a formatted block unchanged.
- `ris doc`: blocks, test imports and helpers are not shown. Gate in
  step 3: the doc of a module with a block has no description string.
- `ris check test` runs `ris test` on the 4.6 lists; nothing new.

### 4.10 SPEC and upstream

SPEC.md gets clauses for 4.1 to 4.5 with a SPEC_CHANGELOG entry naming
this folder. Test blocks do not need tape, so by AGENTS.md they belong
in iyi: list them in UPSTREAM.md.

## 5. Steps, each with a gate in test/cli/

1. The shared walk (4.6) and B1. Gate: a project with a failing test
   under lib/ and one under a dot dir: `ris test` passes.
2. `ris init` header and the error hint (4.8). Gate: init, add `import
   demo` to the test, `ris test` builds it; `ris spec` still counts
   1.1 as todo.
3. Grammar, strip, place rules (4.1, 4.2), formatter and doc (4.9).
   Gate: `ris build` of a module with a block gives a binary without
   the description string; each refused shape in 4.1 and 4.2 gives its
   message; format and doc as in 4.9.
4. The test program (4.3, 4.5). Gate: a block calling a private def
   passes; a failing block prints `FAIL - path:line description`, the
   next block still runs, exit 1; a todo block gives `TODO` and 77;
   `ris test src/store.ri` runs one module; the wasm32 case.
5. Test-only imports (4.4) and spec tags on blocks with B2 (4.7).
   Gate: a block importing std/dir runs; the module's export metadata
   and the binary of an importer name no std/dir symbol; a cyclic
   test import is refused; a tagged block covers its clause; a stale
   block tag fails `ris check spec`; `ris spec ack` rewrites it.

## 6. Alternatives rejected

- Tests only as programs (today): no private access, far from code.
- A sibling `store_test.ri` sharing the module's scope (Go's
  same-package test files): two files per module, the test still away
  from the def. Koja and the user chose in-file.
- Tests anywhere in the file (Rust's `#[cfg(test)]`): the user chose
  the end of the file; one test section gives 4.4 its boundary.
- Running a module's top-level statements in its test program: a
  module that calls `listen` would never reach its blocks (4.2).

## 7. Open questions

- Q1. Should the block form later replace `test "x" do` inside test
  programs, leaving one form? Recommendation: decide after step 4.
- Q2. A file with top-level statements cannot have blocks (4.2). If
  many existing modules run code at load, the rule bites; check
  blog-demo and samples/ before step 3.

## 8. Follow-up, not this work

- Build and result caching for `ris test`: a rerun with no change takes
  15 s in blog-demo, and one program per module multiplies builds. A
  cache keyed on each test program's inputs; separate draft.
- `--affected FILE` for modules with blocks (FILE in M's closure with
  its test imports), and an LSP "run this test" action.

## 9. What the review changed

- B-1: a module is a header line, not a `module ... end` body (checked
  in init.cr); 4.3 now says blocks are in the top-level scope.
- B-2: exact grammar, `test` reserved at a top-level line start, an
  error per other shape (4.1).
- M-1: `todo` ends only its block; verdict rule (4.5).
- M-2: blocks refused in a file with top-level statements (4.2).
- M-3, M-4: one walk, two lists, fixture marker (4.6).
- M-5, M-6: block key is file + description; ack only rewrites (4.7).
- M-7: helpers may not share a def's name (4.2).
- M-8: output lines, totals, module path argument (4.5).
- M-9, M-10: steps reordered; B1 and init are separate early steps;
  LSP and `--affected` moved to section 8.
- M-11: init writes the tag before the header (4.8).
- Minors: citations fixed, scan is a candidate filter, cycles refused,
  `ris build` skips type-checking sections, gates made observable,
  wasm32 gated, D3 wording unified.
