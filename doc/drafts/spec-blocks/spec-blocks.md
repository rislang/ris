# Draft: spec blocks in module files

Status: amended after EGM review
([consolidated_review_report.md](consolidated_review_report.md));
section 10 says what changed. No compiler code yet.

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
own process with a free port and a temporary directory, and stopped at
the block's end. Each block gets a fresh process. Examples:
`blog.get("/").status_code == 200`, `blog.env["PORT"] = "8080"`.
A local named like the module is an error with the fix.

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

D12 (was Q2). v1 has `blog.run(args, stdin:)` and `blog.file(path,
text)` (5.7). A text check in a spec block uses the existing `=~` with
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

## 3. Goals and non-goals

Goals: a clause is proved next to the code that keeps it, private defs
included; every check names a clause; a program is tested by starting
it, with no harness; a release binary carries no check; `ris test` and
`ris spec` walk the same files; a failure names the clause, file:line
and the values.

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
      store = Store.new
      Post.create(store, hello, "a").as(Post).slug == "hello"
      Post.create(store, hello, "b").as(Post).slug == "hello-2"
    end

    spec 1.5  # A post needs a title and some text.
      Post.create(Store.new, "", "text").is_a?(Refusal)
      Post.create(Store.new, "   ", "text").is_a?(Refusal)
      Post.create(Store.new, "Hello", "").is_a?(Refusal)
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

### 4.3 End of site.ri

    module site

    import post
    ...

    spec 3.4  # A post that is not valid (1.5) is refused with 422; nothing…
      store = Store.new
      answer = Site.new(store).handle(Request.post("/posts", "title="))
      answer.status_code == 422
      answer.body =~ %r{<p class="error">[^<]*title}
      store.empty?
    end

### 4.4 End of blog.ri (a program)

    module blog

    import site
    run(Site.new, port: ENV["PORT"].to_i)

    spec 3.4
      blog.post("/posts", form: {"title" => ""}).status_code == 422
    end

    spec 3.6
      blog.post("/posts", form: {"title" => "Old", "text" => "a"})
      blog.post("/posts", form: {"title" => "New", "text" => "b"})
      page = blog.get("/").body
      page.index("New").not_nil! < page.index("Old").not_nil!
    end

`ris test blog.ri` builds blog.ri without its spec section as a normal
binary, then a test program from the spec section. On the first use
of `blog` in a block the harness starts the binary with `PORT` set to
a free port and the working directory set to a fresh temporary
directory, and waits until the port accepts. `blog.get` and
`blog.post` send to that port.

### 4.5 Output

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
    3.6     covered     blog.ri:10

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

A program file is a file with at least one top-level statement other
than a declaration. The test build keeps its declarations: `import`,
`def`, `struct`, `class`, `enum`, `lib`, `alias`, annotations and
constants whose value is a literal. It drops every other top-level
statement (calls, assignments, constants with computed values). A
kept def that uses a dropped name is a compile error in `ris test`:
"`config` is set by blog.ri's top-level code, which spec blocks do
not run; reach it through `blog` or move it into a def".

A program file's block (D6) sees the kept declarations, plus one
local: the program handle named after the module (5.7).

### 5.6 Test-only imports

An `import` in the spec section is test-only. `ris build`, `ris run`
and `ris doc` drop the whole section before name resolution, so these
imports are not in the module's import DAG, its export metadata (R-1:
a module compiles against its imports' metadata) or the binary.

A test-only import of a module that imports this one is refused: "the
proof of post imports site, which imports post; prove it in site.ri".

`ris build` does not type-check spec sections; `ris check types` and
`ris test` do, so `ris check` still catches a broken block.

### 5.7 The program handle

For a file with top-level code and spec blocks, `ris test FILE`:

1. builds FILE without its spec section as a normal binary (the same
   build `ris build` makes), once per run;
2. builds the test program from the module's scope minus top-level
   code, plus the spec section;
3. in each block, binds the module's name to a `RisProgram` value.

`RisProgram` (std, test-only, not linked into builds):

- `env : Hash(String, String)`: set before first use; starts with
  `PORT` (a free port), and `TMPDIR` and `HOME` both set to the
  block's temp directory. Setting it after start breaks the block
  with the fix ("set `blog.env` before the first request").
- `get(path : String) : HTTP::Client::Response`
- `post(path : String, form : Hash(String, String))` and
  `post(path : String, body : String)`, same result.
- `request(method : String, path : String, headers = HTTP::Headers.new,
  body = "") : HTTP::Client::Response`.
  The first of these starts the server with cwd = the block's temp
  directory, waits up to 10 s for PORT to accept (else the block is
  broken with the program's stderr), then sends. Any status is
  returned; a non-2xx answer is not a failure by itself.
- `stdout : String`, `stderr : String`: what the process has written
  so far.
- `file(path : String, text : String)`: writes *text* to *path* under
  the block's temp directory (parents made). Only before first use;
  after start it breaks the block with the same fix as `env`.
- `run(args = [] of String, stdin : String = "") : RisRun`: for CLI
  programs; starts the binary with *args* and *stdin* in the temp
  directory, waits for exit (the block's timeout applies) and returns
  `stdout`, `stderr` and `status : Int32`. No port wait. Each `run`
  is a new process; `env` and `file` apply to it.
- At the block's end the harness sends SIGTERM, waits 2 s, then
  SIGKILL, and removes the temp directory. A block that never uses the
  handle starts nothing.

Each block gets a fresh process: no state leaks between clauses. A
program that does not read `PORT` cannot be reached; the 10 s timeout
message says so ("blog did not accept on PORT=41237; does it read
ENV[\"PORT\"]?").

A local, parameter or helper named like the module is refused in the
spec section: "`blog` is the running program in a spec block; rename
the local".

`file` and `run` are in v1 (D12).

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

CLI to compiler: today run_one_test shells out to `build FILE -o`
(test.cr:363). `ris test` calls `build --spec FILE -o BIN` instead,
which keeps the spec section and emits the generated `main`; for a
program file it first runs the plain `build FILE`. The test binary
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
and step 7 after step 4, init writes a real check instead of the
todo: `demo.run.stdout == "hello from demo\n"`.

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
4. Program handle (5.7). Gate: a tiny HTTP program; a block's
   `get("/")` passes; two blocks get two processes and ports; no
   process is left after the run; a local named like the module is
   refused.
5. Test-only imports (5.6). Gate: a block importing std/dir runs; the
   binary names no std/dir symbol; a cyclic test import is refused.
6. `ris spec` on blocks, spec.lock, B2 (5.10, 5.14); AGENTS.md and
   spec-cli text. Gate: a block covers its clause; editing the clause
   fails `ris check spec`; `ris spec ack` clears it even with a stale
   old `@V` tag on the clause; an orphan lock line fails; after
   `ris spec ack --from-tags` ris's own `ris check spec` is green.
   Also the clause label (5.15): `ris check --fix` writes and
   refreshes it; a stale label fails `ris check`; a long clause is
   cut at a word with `…` within 80 columns; a fresh label alone
   does not clear "to review".
7. `ris init` (5.11). Gate: `ris init demo`, then `ris check` is
   green with 1.1 covered by `demo.run` (D12), and no test/ exists.
8. Remove `test "x" do` (D9) once ris's own test/ is moved. Gate:
   `ris check` green with test/ holding only test/cli/ and test/speed/.

## 7. Alternatives rejected

- Tests only as programs (today): no private access, far from code.
- A description string beside the clause: two names that drift; the
  clause is the name (D1).
- `assert` on each line: noise; a Bool line is enough (D3).
- A harness library for programs: each project rewrites it (D6).
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
