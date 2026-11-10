# Draft: spec blocks in module files

Status: steps 1-3 built. D16-D18 (2026-11-11) replace the program
handle; amended after a second EGM review of the changed sections
([consolidated_review_report.md](consolidated_review_report.md));
section 10 says what changed.

ROOT is the nearest directory up holding `ris.mod` or `iyi.mod`
(spec-cli 4.1).

Context: ris is iyi plus Goose's tape memory (AGENTS.md). Today a test
is a whole program, `*_test.ri` under test/, that exits 0 to pass, 1 to
fail, 77 for todo (iyi SPEC's `go test` row: "every `*_test.iyi` is a
program"). Inside one, `test "name" do ... end` (src/iyi/testing.iyi)
runs a named case. `ris spec` ties SPEC clauses to tests by a
`# spec: N.M@VERSION` tag in a test file's leading comments
(doc/drafts/spec-cli/spec-cli.md). Koja's `test` declaration
(doc/reference/koja/design/TESTING.md) is the model for in-file tests.

A module file starts with a `module PATH` header line, not a
`module ... end` body (the files `ris init` writes, init.cr:163);
everything below is the module's top level.

## 1. Problem

- A private def cannot be unit tested: a test program sees only what a
  module exports, so an agent makes the def public or tests it only
  through the whole program.
- The test lives far from the code, so an agent changing
  `Post.slugify` does not see its proofs.
- A test names a SPEC clause only in a comment, and a test may prove
  no clause at all: work the SPEC does not ask for, or a clause the
  SPEC lacks.
- A program (code at the top level, a server) can be tested only by a
  hand-written harness that starts it, picks a port and stops it.

## 2. Decisions (made by the user; not reopened here)

D1. Spec blocks. A module file ends with blocks `spec N.M ... end`,
N.M a SPEC.md clause. There is no description string: the clause text
in SPEC.md is the name, and `ris test` prints it. There is no bare
`test` block and no `keeps`, `never` or `owes`: one keyword, `spec`.
A check that proves no clause is a missing clause: write the clause
first.

D2. `todo "reason"` lives only inside a spec block. The lines before
it are still checked: the block is broken if one fails, else todo.

D3. Inside a spec block every top-level line of type Bool is an
assertion; no `assert` is written (`Post.slugify("!!!") == "post"`).
A failure prints the clause, file:line, the expression text and both
sides of a comparison.

D4. The test unit is the module. `ris test post.ri` builds module
post, its imports, its spec blocks, its `private def` helpers and its
test-only imports into one test program. Exit 0 pass, 1 fail, 77 todo,
as iyi's test model. Other modules' spec sections are not built.

D5. `ris build` and `ris run` leave the spec section out.

D6. A program file (top-level code, e.g. blog-demo's blog.ri ending
in `run(...)`) may hold spec blocks. The test build leaves its
top-level code out. Inside its blocks the module's name (`blog`, the
last path segment of `module blog`) is the running program: the file
is built once as a normal binary, started lazily on first use as its
own process in the block's temporary directory. D17 says how: the
core only runs a process; ports and HTTP come from a package (D18).

D7. Tags carry only N.M. `ris spec ack` keeps each clause's hash in a
lock file, `spec.lock` at ROOT, so `ris check spec` still reports a
changed clause whose proofs were not reviewed.

D8. test/ is no longer needed in an ordinary project. The old
whole-file `# spec:` tags under test/ keep working during the move.

D9. iyi's `test "x" do` method stays for a transition and goes once
spec blocks work.

D10. Later work is listed in section 9, not designed here.

D11 (was Q1). The spec section starts at the first `spec N.M` block;
there is no bare `spec` line. A test-only import goes after the first
block (5.4).

D12 (was Q2). The run and file forms are D16's `tmp.file` and D17's
`demo(...)` (5.7). A text check in a spec block uses the existing `=~` with
a Regex (std/regex); the suggested form is `%r{...}`, so HTML needs no
escaped `/` (the lexer already reads `%r` with `{`, `(`, `[`, `<` or
`|`: lexer.cr, delimiter_state_for_percent_literal). There is no `~`,
and examples do not use `includes?`. A failing `=~` line prints the
pattern and the text (5.2).

D13 (was Q3). No special refusal for `x = a == b`. An assignment line
is never an assertion, and the type check already refuses most such
lines. A spec block with no assertion line is an error: "spec 1.2 at
post.ri:19 checks nothing; add a line that is a Bool" (5.2).

D14 (was Q4). One rule lives in one clause; other clauses refer to it
by number. blog-demo gets `1.5 A post needs a title and some text.`
(proved in post.ri), and 3.4 becomes `A post that is not valid (1.5)
is refused with 422; nothing is written.` (proved in site.ri). The
planned AGENTS.md text says so (5.13).

D15. A block may carry its clause text as a comment:
`spec 1.5  # A post needs a title and some text.` The tools keep it:
`ris check --fix` writes or refreshes it from SPEC.md, and `ris check`
fails on a stale one. It is optional, but when present must match
(5.15). It is a label, not a review: `ris spec ack` is still needed
after a clause changes.

D16 (2026-11-11). Every spec block, module or program file, has `tmp`:
the block's own temporary directory, removed at the block's end.
`tmp.path`, `tmp.file(path, text)` (parents made), `tmp.read(path)`,
`tmp.children(path = ".")`. A Store proof writes `Store.new(tmp.path)`.
A local, parameter or helper named `tmp` in a spec section is refused.

D17 (2026-11-11). In a program file's spec section the module's name
(`demo`) runs the plain binary in `tmp` to its end and returns a
RisRun (5.7 has the signatures). `==` and `=~` with a
String or Regex compare its stdout; it has `.status`, `.stderr`,
`.stdout`. Every call is a new process (`out = demo` to reuse one). A
failing line prints stdout, stderr and status. `demo.start(args,
env:)` starts it in the background and returns a RisProcess:
`wait_for(regex, timeout)`, `write(text)` to its stdin, `stdout`,
`stderr`, `stop`, `status`; it is stopped (SIGTERM, 2 s, SIGKILL) at
the block's end. `free_port` is a core helper. No `port`, `url`, `get`,
`post`, `request` and no port wait in the core: that is protocol
knowledge for packages (D18). A local named like the module is refused.

D18 (2026-11-11). A package may ship test vocabulary as a module
`<package>/spec` (web/spec: `get(program, path)`, `post`, `browse`).
A spec section imports it explicitly (`import web/spec::*`); importing
a `*/spec` module anywhere else is refused with the fix. When a name is
undefined in a spec block and a directly imported package's spec module
defines it, the error names the import to add. web/spec itself is later
work in rispacks/web (section 9).

## 3. Goals and non-goals

Goals: a clause is proved next to the code that keeps it, private defs
included; every check names a clause; a program is tested by running
it, with no harness; protocol helpers live in packages (D18); a
release binary carries no check; `ris test` and `ris spec` walk the
same files; a failure names the clause, file:line and the values.

Non-goals: no suites or nesting; no description strings; no new
matcher library beyond what section 8 asks; no result cache; no
`--affected` or LSP work (section 9).

## 4. Worked example: blog-demo

### 4.1 SPEC.md excerpt (partial)

    ## 1. Posts
    * 1.1 A post's slug is its title in lower case, words joined by `-`.
    * 1.2 A title with no letters or digits gives the slug `post`.
    * 1.3 A post keeps its slug when its title changes.
    * 1.4 Two posts never share a slug; the second gets `-2`.
    * 1.5 A post needs a title and some text.
    ## 3. Site
    * 3.4 A post that is not valid (1.5) is refused with 422; nothing
      is written.
    * 3.6 The front page lists posts, newest first.

The rule for a valid post lives only in 1.5; 3.4 refers to it by
number (D14).

### 4.2 End of post.ri

    module post

    struct Post
      getter title : String
      getter slug : String
      def self.slugify(title : String) : String
        ...
      end
      def self.create(store : Store, title : String,
                      text : String) : Post | Refusal
        ...
      end
    end

    spec 1.1  # A post's slug is its title in lower case, words joined…
      Post.slugify("Tere Öö") == "tere-öö"
      Post.slugify("  two   words ") == "two-words"
    end

    spec 1.2
      Post.slugify("!!!") == "post"
      Post.slugify("") == "post"
    end

    spec 1.4
      store = Store.new(tmp.path)
      Post.create(store, hello, "a").as(Post).slug == "hello"
      Post.create(store, hello, "b").as(Post).slug == "hello-2"
    end

    spec 1.5  # A post needs a title and some text.
      store = Store.new(tmp.path)
      Post.create(store, "", "text").is_a?(Refusal)
      Post.create(store, "   ", "text").is_a?(Refusal)
      Post.create(store, "Hello", "").is_a?(Refusal)
      tmp.children == [] of String
    end

    spec 3.4
      todo "the model has no HTTP; site.ri proves it"
    end

    private def hello : String
      "Hello"
    end

`spec 3.4` here is only to show `todo`; 3.4 is proved in site.ri and
blog.ri. A clause with one real block is covered even beside a todo
block (5.14). The 1.1 comment is cut at a word to fit 80 columns (D15).
`tmp` is the block's own directory (D16): Store writes there, and the
1.5 block checks that a refused post wrote nothing.

### 4.3 End of site.ri

    module site

    import post
    ...

    spec 3.4  # A post that is not valid (1.5) is refused with 422; nothing…
      store = Store.new(tmp.path)
      answer = Site.new(store).handle(Request.post("/posts", "title="))
      answer.status_code == 422
      answer.body =~ %r{<p class="error">[^<]*title}
      store.empty?
    end

### 4.4 End of blog.ri (a program)

    module blog

    import site
    run(Site.new(Store.new("data")), port: ENV["PORT"].to_i)

    spec 3.4  # A post that is not valid (1.5) is refused with 422; nothing…
      post(blog, "/posts", {"title" => ""}).status == 422
    end

    import web/spec::*

    spec 3.6
      page = browse(blog)
      page.visit("/posts/new")
      page.fill("Title", "Old")
      page.fill("Text", "a")
      page.click("Publish")
      page.visit("/posts/new")
      page.fill("Title", "New")
      page.fill("Text", "b")
      page.click("Publish")
      page.visit("/")
      page =~ %r{New.*Old}m
    end

`post` and `browse` are not core: they come from web/spec, later work
in rispacks/web (D18, section 9). The core gives web/spec what it
needs: `blog` as an argument is the program (5.7); web/spec starts it
with `PORT` set to `free_port`, in `tmp`. The import follows the first
block, as every test-only import (D11), and serves every block of the
file, above it too: an import is file-wide (5.6).

### 4.5 A CLI program

`ris init demo` writes demo.ri; its spec section uses only the core:

    module demo

    puts "hello from #{ARGV[0]? || "demo"}"

    spec 1.1  # Running demo.ri prints `hello from demo`.
      demo == "hello from demo\n"
      demo("ris") =~ %r{ris}
    end

`ris test demo.ri` builds demo.ri as `ris build` does, then the test
program; each `demo` line runs the binary once in the block's `tmp`.

### 4.6 Output

`ris spec` reports coverage from the source; it runs nothing (5.14):

    $ ris spec
    clause  state       proofs
    1.1     covered     post.ri:14
    1.2     covered     post.ri:19
    1.3     uncovered
    1.4     covered     post.ri:24
    1.5     covered     post.ri:30
    3.4     covered     site.ri:41, blog.ri:6
            todo        post.ri:36
    3.6     covered     blog.ri:12

`ris test` runs the blocks and gives pass, broken or todo:

    $ ris test
    ok   1.1 post.ri:14  A post's slug is its title in lower ...
    FAIL 1.2 post.ri:19  A title with no letters or digits ...
    TODO 3.4 post.ri:36  the model has no HTTP; site.ri proves it
    ...
    3 modules, 8 blocks: 6 ok, 1 broken, 1 todo

A broken clause:

    FAIL spec 1.2  A title with no letters or digits gives the slug
                   `post`.
      post.ri:21  Post.slugify("") == "post"
        left:  ""
        right: "post"

## 5. Design

### 5.1 Grammar

A spec block is a top-level declaration of exactly this shape:

    spec N.M NEWLINE
      statements
    end

- N.M is a clause number literal: digits, a dot, digits (also N.M.K
  if SPEC.md nests). Nothing else may follow it on the line but a
  comment, the clause text's label (D15, 5.15).
- `spec` at the start of a top-level line is reserved for this form.
  Any other shape there is an error with the fix:
  `spec "text"` ("a spec block names a SPEC.md clause: `spec 1.2`;
  the clause text is its name"), `spec 1.2 do`, `spec` with no number.
  `def spec` at top level is refused ("`spec` starts a spec block;
  name the def otherwise").
- `test "x"` at a top-level line start in a file with a spec section
  is refused: "a check names a SPEC clause: write `spec N.M`; add the
  clause to SPEC.md first if none fits". Old `*_test.ri` programs keep
  `test "x" do` during the move (D8, D9); step 8 refuses it
  everywhere.
- An unknown clause (not in ROOT's SPEC.md) is a compile error in
  `ris test` and `ris check`: "no clause 1.9 in SPEC.md; add it there
  first, or name the clause this proves". No SPEC.md at ROOT: the
  same error, naming the file to create.
- Two blocks in one file may name the same clause: allowed (a clause
  may need setups that would collide). Their key is file + clause +
  ordinal (5.8).

### 5.2 Lines that assert

Inside a block, every statement at the block's top level whose static
type is exactly `Bool` is an assertion (D3). A statement of another
type runs for its effect. A `Bool?` or other union with Bool is
refused: "line 12 may be nil; write `x == true`". A Bool inside a
nested `if`, loop or block body is not an assertion; write it at the
block's top level or call `assert`, which panics (block broken).

Lowering: after typing, the pass that strips or keeps the spec
section rewrites each asserting line. `a OP b`, OP one of `==`, `!=`,
`<`, `<=`, `>`, `>=`, becomes
`__ris_spec_check(a, b, "OP", TEXT, FILE, LINE)`; any other Bool `e`
becomes `__ris_spec_check(e, TEXT, FILE, LINE)`. TEXT is the line's
source text. The runtime defs (std, test-only) record a failure with
both sides' `inspect` in the block's record and return; they never
panic.

- A failed line does not stop the block: later lines still run, so one
  run shows every failed line. A panic stops the block (broken).
- A Bool call whose result is meant to be ignored (`set.add?(x)`)
  becomes an assertion too; write `_ = set.add?(x)` to drop it. When
  such a line fails the message names the fix: "line 12 is a Bool, so
  it is checked; write `_ = ...` to run it without checking".
- An assignment at the top level is never an assertion, even of a
  Bool (`ok = x > 1`); there is no special refusal for `a.b = c == d`
  (D13): the type check already refuses most such lines.
- A text check is `text =~ %r{...}` (D12). `String#=~` returns
  `Int32?`, not Bool, so a top-level `a =~ b` line with a Regex on
  either side is an assertion as its own form: it is lowered to
  `__ris_spec_match(a, b, TEXT, FILE, LINE)`, which fails when the
  match is nil and prints the pattern and the text.
- A block with no assertion line and no `todo` is refused (D13):
  "spec 1.2 at post.ri:19 checks nothing; add a line that is a Bool".

As built (step 3): the parser lowers the section before typing, since a
pass after typing would need a second typing of the rewritten lines.
Each candidate line becomes a call to `RisSpecRun` (testing.iyi, in the
prelude; unused code is not linked) whose overloads check only a Bool;
a generic def per block receives `Tuple(typeof(line)...)` and its macro
raises the `Bool?` and "checks nothing" refusals. Same rules, same
messages; a `Bool?` refusal also names the block.

### 5.3 todo

`todo "reason"` is valid only as a top-level statement of a spec block
(D2); elsewhere it is refused: "`todo` marks an unproved clause; put
it in a `spec N.M` block". Lines after `todo` in the same block are
refused ("nothing runs after `todo`; move it to the end of the
block").

The block's verdict: broken if a line before `todo` failed or
panicked, else todo. todo ends only its block. Today `todo` is a
prelude def (src/iyi/prelude.iyi:2442) that exits 77 and ends the
program, and IyiTestCases.verdict (testing.iyi:201) knows only 0 and
1. In a spec block `todo` is lowered to a test-only call that records
the reason and returns from the block; the verdict gains a todo
count.

### 5.4 Place: the spec section

The first `spec` block starts the file's spec section; it runs to the
end of the file (D11; there is no bare `spec` line).
The section may hold only spec blocks, `import` lines (test-only,
5.6) and `private def` helpers.

The compiler enforces it: anything else after the first block is
refused with the fix: "`def render` comes after the spec block at
post.ri:14; move it above the first `spec`: proofs go at the end of
the file". The formatter does not reorder code.

A helper may not share a name with a def above the section ("the
helper `slugify` would replace the code under proof; rename it").
Code above the section cannot call a helper: in a build the section
does not exist.

### 5.5 What a block sees

A module file's block is compiled in the module's top-level scope, as
a private def would be: it sees private defs, types and constants and
may call them qualified (`Post.slugify`) or not. It sees the module's
imports, its test-only imports and its helpers. Nothing outside the
file sees a block or a helper.

Every block, in a module or a program file, also sees `tmp` (D16,
5.7).

A program file is a file with at least one top-level statement other
than a declaration before its spec section. The test build keeps its
declarations: `module`, `import`, `def`, `macro`, `struct`, `class`,
`module ... end`, `enum`, `lib`, `alias`, annotations and constants
whose value is a literal. It drops every other top-level statement
(calls, assignments, constants with computed values). A kept def that
uses a dropped name is a compile error in `ris test`: "`config` is set
by blog.ri's top-level code, which spec blocks do not run; reach it
through `blog` or move it into a def". The check sees a dropped local
or constant named in a kept body; a name reached another way (a macro)
fails later as an undefined name.

A program file's block sees the kept declarations, `tmp`, and the
module's name as a generated private def that runs the program (D17,
5.7).

### 5.6 Test-only imports

An `import` in the spec section is test-only. `ris build`, `ris run`
and `ris doc` drop the whole section before name resolution, so these
imports are not in the module's import DAG, its export metadata (R-1:
a module compiles against its imports' metadata) or the binary.

A test-only import of a module that imports this one is refused: "the
proof of post imports site, which imports post; prove it in site.ri".

`ris build` does not type-check spec sections; `ris check types` and
`ris test` do, so `ris check` still catches a broken block.

### 5.7 tmp and the program (D16, D17)

The core is what any program needs: a directory and a process. It
knows no port and no protocol; those live in package spec modules
(D18, 5.16).

`tmp` (every block): a RisTmp. The parser makes it the block's first
local and `defer`s its removal, so a panic removes it too.

- `tmp.path : String`: the block's directory, made fresh under the
  system temp directory when the block starts, removed with all it
  holds when the block ends.
- `tmp.file(path, text) : Nil`: writes *text* to *path* under it,
  parents made.
- `tmp.read(path) : String`.
- `tmp.children(path = ".") : Array(String)`: the names in a directory
  under it, sorted.

For a program file `ris test FILE` first builds FILE as `ris build`
does, once per run, and gives the test program its path. In the spec
section the module's name (`demo`, the last segment of `module demo`;
without a header the file's base name) is a generated private def:

    demo(*args : String, stdin = "", env = {} of String => String)

It runs the binary with *args* in `tmp` and waits for its end. The
child's environment is the test program's, less `RIS_SPEC_JSON` and
`RIS_SPEC_PROGRAM`, with `HOME` and `TMPDIR` set to `tmp.path`, then
*env*. *stdin* is written to it (std/process `Process.run`). There is
no per-block timer: `ris test --timeout` kills the whole test binary
and the processes it started (TestTree), and the running block is
reported broken. It returns a RisRun (`@[OnTape]`, on the block's
tape):

- `stdout`, `stderr : String`, `status : Int32` (std/process's
  `exit_code`: 128 + N after signal N on Linux and darwin);
- `==(text : String) : Bool` compares stdout; `=~(pattern : Regex) :
  Int32?` matches stdout; a failed `=~` line prints the Regex as the
  pattern and the RisRun as the text;
- `inspect` shows stdout, stderr and status, so a failing line prints
  all three.

Every call is a new process; `out = demo` keeps one run.

`demo.start(args = [] of String, env = {} of String => String)`
starts it in the background, in `tmp` as above, and returns a
RisProcess:

- `wait_for(regex, timeout = 10) : Bool`: true once stdout matches,
  false after *timeout* seconds or when the process ended first; as a
  block line it is an assertion. It polls every 20 ms (`sleep`);
- `write(text)`: to its stdin;
- `stdout`, `stderr : String`: what it has written so far;
- `stop : Int32`: SIGTERM, 2 s (polled), SIGKILL; returns the status;
- `status : Int32?`: nil while it runs.

Its stdout and stderr go to two files beside `tmp` (not in it, so
`tmp.children` does not see them) through `/bin/sh -c 'exec ...'`, so
no pipe fills and nothing must drain it; stdin is a pipe. Linux and
darwin only: on Windows and wasm32 `demo` and `start` panic with the
reason; `tmp` works everywhere.

At the block's end every process the block started is stopped as
`stop` does, then `tmp` is removed. The lowering writes
`demo.start(...)` as `tmp.started(RisProgram.new("demo",
tmp).start(...))`: the process is made in the block's scope, as tape
requires of a value `tmp` keeps (SPEC 1.1). A package helper that
starts a process hands it to `tmp.started` the same way, from the
block; one started inside the helper alone would be refused.

The module's name has two meanings, chosen by its place in the source
as written; the parser rewrites a block's lines before it lowers them
to assertions (5.2), so the lowering's own calls do not count:

- `demo.start(...)`: the program, started (above);
- `demo` with no arguments as a positional or named argument of a call
  that is not an operator (`browse(demo)`, `get(demo, "/")`): the
  program itself, a RisProgram with `name`, `path` and `start`;
- everywhere else, including `demo == ...`, `demo =~ ...` and
  `x == demo`: a run, `demo(tmp, ...)` of the generated def.

A package helper takes a RisProgram and decides how to start and reach
it (D18). Only block lines are rewritten: a helper def in the section
that needs the program takes it as a parameter.

`free_port : Int32` (every block): a TCP port on 127.0.0.1 that was
free when asked. Another process may take it before the program
binds; a package helper that sees the bind fail retries once with a
new port. The core knows ports only this far.

A local, parameter or helper named `tmp`, or named like the module in
a program file, is refused in the spec section: "`tmp` is the block's
temporary directory in a spec block; rename the local", "`demo` runs
the program in a spec block; rename the local".

RisTmp, RisRun, RisProcess, RisProgram and `free_port` live in
std/ris_spec (built on std/process, std/dir, std/file). `ris build
--spec` (`ris_lower_spec`) inserts `import std/ris_spec::{...}` after
the module header; nothing else imports it, so a `ris build` binary
has none of them. RisSpecRun, the assertion runtime of 5.2, stays in
the prelude (testing.iyi), where unused code is not linked.

The check of 5.5 for a dropped name matters for computed constants
(`CONFIG = load`): a kept def that reads a top-level local does not
compile in a plain build either, so `ris test` reports the plain
build's error first.

### 5.8 The test program and verdicts

For module M, `ris test` builds one program: M's scope with its spec
section, M's imports without theirs, and a generated `main` that runs
the blocks one after another in file order, each in a task of its own
that `main` awaits before the next (as testing.iyi runs a named case:
a panic ends only its block). Failed lines and todo are recorded per
block on every target. On wasm32 (no tasks) only a panic differs: it
ends the program and is reported against its block. Program verdict:
1 if any block broke, else 77 if any was todo, else 0.

A block's key is file + clause + its ordinal among that file's blocks
for the clause; reports show file:line.

Tape: each block is a def body and frees its temporaries when it ends
(ris SPEC.md 1.1).

CLI to compiler: run_one_test calls `build --spec FILE -o BIN`,
which keeps the spec section and emits the generated `main`; for a
program file it first runs the plain `build FILE` and passes its path
to the test binary in `RIS_SPEC_PROGRAM` (5.7). The test binary
writes one JSON line per block to stdout when `RIS_SPEC_JSON=1`:
`{clause, ordinal, file, line, status, failures, reason}`; `ris test
--json` passes them on. `--timeout` applies per block (the harness
kills the test binary and marks the running block broken).

`ris test` with no argument runs every module with blocks (5.9) and
the old test programs under test/ (D8); `ris test FILE` runs one
module; it sums: `3 modules, 8 blocks: 6 ok, 1 broken, 1 todo`.

### 5.9 One walk for `ris test` and `ris spec`

One function walks ROOT and returns two lists:

- modules with blocks: `.ri` / `.iyi` files whose parse holds a spec
  section (a scan for a line starting `spec ` picks candidates; the
  parse decides);
- old files under ROOT/test/: today's spec_walk set (any `.ri`,
  `.iyi`, `.cr`, `.sh`, `.py`) for `ris spec`, and of those the
  `*_test.ri` / `*_test.iyi` programs for `ris test`.

It skips `lib/`, `mods/`, every directory whose name starts with a
dot, fixture trees (a directory holding a `.ris-fixtures` marker) and
symlinks, as spec_walk does. Suffixes match in any case, and
test.cr's refusal of a miscased test name (test.cr:121) stays.
Bugs this fixes:

- B1. `ris test` with no path walks `.` with `**/*_test.ri`
  (test.cr:107), so it runs tests under lib/, which belong to another
  project. Fixed in step 1.
- B2. `ris spec` reads only test/, so blocks in src/ would be missed.
  Fixed in step 6.

### 5.10 Clause hashes: spec.lock

Tags no longer carry `@VERSION`. The hash is spec-cli 4.2's clause
version, unchanged (spec_version: SHA-256 of the clause text from
`N.M` to the next clause or heading, nested clauses excluded,
whitespace collapsed; first 8 hex). `ris spec ack N.M` (after review)
writes N.M and that hash to ROOT/spec.lock, one line per clause,
sorted:

    1.1 7c3e09a2
    1.2 a1f4b6d0

`ris check spec` fails:

- when a clause with proofs has no lock line or a different hash
  ("1.2 changed since its proofs were reviewed: review post.ri:19,
  then `ris spec ack 1.2`");
- when a clause is uncovered ("1.3 has no proof; add `spec 1.3` at
  the end of the module that keeps it");
- on a lock line for a clause SPEC.md no longer has (orphan);
  `ris spec ack` removes orphans.

The SPEC_CHANGELOG check stays as it is (spec_clauses.cr:575): each
clause version needs a `N.M@HASH` changelog heading; the hash is the
same one the lock holds.

Move from old tags: an old file tag `# spec: N.M@V` under test/ keeps
counting as a proof of N.M. Once spec.lock holds a line for N.M, the
tag's `@V` is ignored; before that, a tag's `@V` that differs from the
clause fails as today. `ris spec ack --from-tags` seeds spec.lock with
every clause whose tags all match its current version; step 6 runs it
on ris itself. spec.lock is committed.

### 5.11 `ris init`

Today `ris init demo` writes demo.ri, SPEC.md with clause 1.1
("Running demo.ri prints `hello from demo`.", init.cr:196),
SPEC_CHANGELOG.md with its `1.1@HASH` heading, AGENTS.md teaching
`# spec:` tags (init.cr:215-218), and test/demo_test.ri holding a
`# spec: 1.1@HASH` tag and a `todo`, with no `module` header, so a
first `import demo` added to it fails to resolve.

Instead init writes no test/. demo.ri ends with:

    spec 1.1
      todo "run demo.ri and check that it prints `hello from demo`"
    end

and init writes spec.lock with 1.1's line. AGENTS.md's text and the
usage text (init.cr:223-234) teach spec blocks instead of tags.
SPEC.md and SPEC_CHANGELOG.md are unchanged. With `run` in v1 (D12)
step 7 (after step 4) has init write a real check instead of the
todo: `demo == "hello from demo\n"` (4.5).

### 5.12 Tools

- Formatter: formats blocks like defs, keeps them in place; never
  joins a Bool line into another.
- `ris doc`: the spec section is not exported.
- `ris check test` runs `ris test` on the 5.9 lists.
- `--affected` and LSP: section 9.

### 5.13 SPEC and upstream

SPEC.md gets clauses for 5.1 to 5.12, 5.14 and 5.15 with a SPEC_CHANGELOG
entry naming this folder. AGENTS.md (its `# spec: N.M@VERSION` and
test/spec/ rule) and spec-cli's tag sections (6.7 to 6.9) are
rewritten for spec blocks in step 6. Spec blocks do not need tape:
list them in UPSTREAM.md for iyi.

The planned AGENTS.md text also gains (D14): "A rule lives in one
clause; other clauses refer to it by number."

### 5.14 Clause states

`ris spec` reads source only; it never runs a test. Its states keep
today's names (SPEC_STATUSES, spec_clauses.cr:394):

- covered: at least one block or old test names N.M without `todo`;
- todo: only todo blocks or todo tests name it;
- uncovered: nothing names it;
- to review: covered or todo, but spec.lock lacks its current hash.

Pass, broken and todo outcomes come only from `ris test`. `ris check`
runs both, so a covered clause with a broken block still fails it.

### 5.15 The clause label

A block's line may end in a comment holding the clause text (D15):

    spec 1.5  # A post needs a title and some text.

The label is optional; when present it must match SPEC.md. The clause
text is whitespace-collapsed as for the hash (5.10). If the line would
pass 80 columns, the text is cut at the last whole word that fits and
ends in `…`; a label matches when it equals that cut form.

- `ris check --fix` writes a missing label and refreshes a stale one.
- `ris check` (its spec step) fails on a stale label: "the label of
  spec 1.5 at post.ri:30 differs from SPEC.md; run `ris check --fix`".
  A block without a label passes.
- A label is not a review. Refreshing it does not touch spec.lock:
  after a clause changes, `ris spec ack N.M` is still needed (5.10).

Step 6 builds it, beside spec.lock: both read the clause text.

### 5.16 Package spec modules (D18)

A package `p` may ship a module `p/spec` with test vocabulary: defs a
spec block calls, taking a RisProgram, RisProcess or `tmp` from the
core. A spec section imports it like any test-only import (5.6):
`import web/spec::*`. An import of a module whose last segment is
`spec` (two segments or more) anywhere but in a spec section is
refused: "web/spec is test vocabulary; import it after the first
`spec` block". The module `p/spec` itself may import other spec
modules. A project whose own module is named `x/spec` for another
reason renames it.

When a name in a spec block is undefined and the spec module of a
package in the file's import closure defines it, the error adds:
"web/spec defines `get`; add `import web/spec::*` after the first
`spec` block". The closure, not only direct imports: blog.ri reaches
web through site. Step 6 builds it.

## 6. Steps, each with a gate in test/cli/

1. Shared walk (5.9), B1. Gate (test/cli/test_walk.sh): a failing
   test under lib/, mods/ and a dot dir; `ris test` passes and runs
   only the root one.
2. Grammar, place, strip (5.1, 5.4, 5.6 strip only), formatter, doc.
   Gate: `ris build` binary has no block's string; each refused shape
   gives its message; format leaves a block unchanged; doc omits it.
3. Module test program (5.2, 5.3, 5.5, 5.8). Gate: a block on a
   private def passes; a failing line prints clause, file:line,
   expression and both sides, the next line still runs, exit 1; todo
   gives 77; an unknown clause is refused.
4. tmp and the program (5.5, 5.7, 5.16 refusal). Gate
   (test/cli/spec_blocks_program.sh): a module block uses
   `tmp.file`, `tmp.read`, `tmp.children` and the directory is gone
   after; a CLI program: `demo == "...\n"`, a status, stdin, env and a
   failing line printing stdout, stderr and status; a background
   program: start, `wait_for` a ready line, write to stdin, `wait_for`
   its echo, no process left (pgrep); a kept def using a dropped name
   is refused; locals named `tmp` or like the module are refused; a
   `*/spec` import above the section is refused; the plain build has
   no RisRun or RisProcess symbol. The undefined-name hint (5.16)
   moves to step 6: it needs the type check's error path. Not in the
   gate: a panicking block's `tmp` (the `defer` covers it).
5. Test-only imports (5.6). Gate: a block importing std/dir runs; the
   binary names no std/dir symbol; a cyclic test import is refused.
   Done (test/cli/spec_blocks_imports.sh). Steps 2-4 already dropped
   the section from build, .iyimod and doc. `ris test` refuses the
   cycle before the build, which would only say "import cycle".
   `--affected` did not count the section: the closure parse dropped
   it, and it probed only `.iyi`, so no `.ri` module was reached at
   all; the entry is now parsed with its section and `.ri` comes first.
6. `ris spec` on blocks, spec.lock, B2 (5.10, 5.14); AGENTS.md and
   spec-cli text. Gate: a block covers its clause; editing the clause
   fails `ris check spec`; `ris spec ack` clears it even with a stale
   old `@V` tag on the clause; an orphan lock line fails; after
   `ris spec ack --from-tags` ris's own `ris check spec` is green.
   Also the clause label (5.15): `ris check --fix` writes and
   refreshes it; a stale label fails `ris check`; a long clause is
   cut at a word with `…` within 80 columns; a fresh label alone
   does not clear "to review". The 5.16 hint: a block calling `get`
   in a file that imports web (directly or through site) without
   web/spec names the import.
   Done (test/cli/spec_blocks_lock.sh). The 5.16 hint comes from
   `ris test`, which reads the build's "undefined" lines, not from the
   type check: the same text where an agent runs a block. `ris spec
   ack` locks only clauses with proofs. ris's own test/ris/check.sh had
   a tag broken by a rewrap; it is fixed. SPEC 6.9's `ris init`
   sentence waits for step 7.
7. `ris init` (5.11). Gate: `ris init demo`, then `ris check` is
   green with 1.1 covered by `demo == "hello from demo\n"` (4.5), and
   no test/ exists.
8. Remove `test "x" do` (D9) once ris's own test/ is moved. Gate:
   `ris check` green with test/ holding only test/cli/ and test/speed/.

## 7. Alternatives rejected

- Tests only as programs (today): no private access, far from code.
- A description string beside the clause: two names that drift; the
  clause is the name (D1).
- `assert` on each line: noise; a Bool line is enough (D3).
- A harness library for programs: each project rewrites it (D6).
- HTTP in the core program handle (`blog.get`, a port wait): protocol
  knowledge in the compiler; a package's spec module carries it (D17,
  D18).
- Hash in the tag (`@VERSION`): every ack edits test files; the lock
  keeps tags stable (D7).

## 8. Open questions for the user

None: Q1 to Q4 were answered as D11 to D14.

## 9. Follow-up, not this draft

- Runnable README and doc/ examples (```sh and ```http blocks run
  against the program), linked to SPEC chapters by
  `<!-- spec: N -->` as a review reminder, not one-to-one.
- Build and result caching for `ris test`.
- `for any` property lines.
- `ris test --mutate`.
- `ris test --affected FILE`: modules whose closure (with test-only
  imports) holds FILE, and program files importing it.
- LSP: hover on `spec 1.2` shows the clause; go-to opens SPEC.md.
- web/spec in rispacks/web (D18), its own draft: `get(program, path)`
  and `post` start the program with `PORT=free_port` and wait until
  the port accepts; a Capybara-style `browse(blog)` with `visit`,
  `fill(label, value)`, `click(text)`, `path`, `status` and
  `page =~`.

## 10. What the review changed

- B-1, M-1: the lock hash is spec-cli's clause version; the
  SPEC_CHANGELOG check stays; orphan lock lines (5.10).
- B-2, M-2: a lock line overrides an old tag's `@V`; `--from-tags`
  seeds the lock (5.10, step 6).
- M-3: clause states defined; `ris spec` reports coverage only (5.14,
  4.5).
- M-4: what a program file's test build keeps and drops (5.5).
- M-5: `test "x"` refused only beside a spec section until step 8.
- M-6: Bool lowering, `Bool?` refused, `assert` panics (5.2).
- M-7: blocks run in order; wasm32 differs only on panic (5.8).
- M-8: `build --spec`, JSON lines, per-block timeout (5.8).
- M-9: typed RisProgram API; init writes the todo form (5.7, 5.11).
- M-10: init's real output and the walk's file rules (5.9, 5.11).
- Minors: counts, excerpt bullets and 1.3, `includes?` for `~`,
  column, AGENTS.md and spec-cli edits in step 6, where `todo` lives,
  `--affected` and LSP moved to section 9, wording.

Second review (2026-11-11, D16-D18 and the sections they touch):

- B-1, m-13: the module name's two meanings are fixed in the source
  before lowering (5.7).
- B-2: no per-block timer; `--timeout` kills the binary and its
  children (5.7).
- M-1: 5.11 and step 7 use `demo == ...`.
- M-2: a timeout kill takes the children with it (TestTree); a killed
  binary's `tmp` may stay in the system temp directory.
- M-3: a section import is file-wide (4.4).
- M-4, m-7: std/ris_spec and how it is imported (5.7).
- M-5: RisRun's `==` and `=~`; `match` labels by the side that is not
  the text (5.7; testing.iyi fixed).
- M-6, M-7: status is std/process's exit code; waits poll; output goes
  to files; Linux and darwin only (5.7).
- M-8: the child's environment (5.7).
- M-9: the hint looks at the import closure; step 6 gates it.
- Built in step 4 and changed by it: `demo.start` registers through
  `tmp.started` in the block (tape); the dropped-name check matters
  for computed constants (5.7).
- Minors: D12/D17 cite 5.7, the Goals line, 5.8's stale test.cr
  line, 4.6's line number, `free_port`'s race, `*/spec` refusal
  scope, step 4 gate scope.
