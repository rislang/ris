# Draft: OptionParser on ris, values read after parse

## Change

Make `std/option_parser` build in ris programs. Every option, String
options included, gets one form ris accepts: register the flags,
parse, then read what the command line gave.

    parser = OptionParser.new
    verbose = parser.on("-v", "--verbose", "say more")
    ending = parser.on("-e EXT", "ending")
    help = parser.on("-h", "--help", "this help")
    found = RisOptions.new
    rest = parser.parse(Program.args, found)
    if found.has?(help)
      puts parser
      exit
    end
    ext = found[ending]? || ".txt"

`on` answers a `RisFlag`, a handle to the registration. `found` is
read through these handles, so a misspelled flag is an undefined local
at compile time, and each flag's text is written once.

`found` holds views of `args` only (a view: `doc/TAPE_API.md`). The
existing root checks (SPEC 3.1, 3.2) prove each store. `HeadParser`
in `AGENTS.md` works the same way. Nothing the parser keeps is made on
a def's scratch (the storage a def frees when it ends, SPEC 1.1).

The block forms (`on(…) { }`, `invalid_option { }`,
`missing_option { }`), commands and `parse(args)` are removed. A block
form called in a program is a compile error at the caller's line that
shows the form above.

No SPEC rule changes; no compiler change. New: the types `RisOptions`
and `RisFlag`, `on` without a block answering a `RisFlag`,
`parse(args, found)` and `record_errors`.

Goals, checked by the gates in the plan: the blocked trial program's
case builds and reads `-e`; Crystal's block form gets the stub message;
`RIS_TAPE_STATS=1` reports no growth moves for a parse.

Words used here: "the agent" is the agent that writes a ris program
(`AGENTS.md`, Agent first); a "panic" is a `raise` (SPEC 4.1); probes
are the programs in [probes/](probes/), built with the compiler at
6173b7918.

## Problem

TODO.md lists "OptionParser cannot set a String option". The obstacle
is wider:

* `parser.on("-e EXT", "ending") { |v| ext = v }` is refused: "this
  block becomes a proc, which may run after the tape block that made
  `ext : String` has ended"
  (`samples/ris/trial/blocked/option_parser_string.ri`). A captured
  class instance, an Array, and Crystal's help idiom
  `{ puts parser; exit }`, which captures `parser`, are refused the
  same way.
* A program whose blocks capture only a Bool and an Int32 is refused
  inside the library: `on` stores a String built on its scratch into a
  field (`@help << {"  #{flag}  #{description}", …}`,
  `src/std/option_parser.iyi:117`, `:121`, `:134`; SPEC 1.1, 3.6).
* With that fixed, the library still cannot call a block: a stored
  `String -> Nil` proc called with a view is refused, "cannot prove
  opaque callback retain/escape effects". Every `on` block and both
  handlers have that type.
* No build mode accepts the block form. The compiler sets `ris_no_gc`
  for every program (`src/compiler/iyi/compiler.cr:2833`); `bin/iyi`
  and `bin/ris` are one binary. `bench/std_option_parser_exercise.sh`,
  the library's only exercise, fails at its first block.
  `test/ris/check.sh` imports the module (`std_text_plain.ri`) but
  never calls it.

The refusals catch a real fault: `ext = v` stores the block's argument
into a local that outlives the call, through a call whose target is
unknown (SPEC 3.4). A `parse(args)` given an array built in a loop
round would leave `ext` viewing freed scratch.

| Probe | Shape | Result |
| --- | --- | --- |
| p2 | blocks capturing a Bool and an Int32 | refused in `on` |
| p3, p4 | a block or `->` capturing a class / String | refused |
| p7 | a stored `String -> Nil` proc called with a view | refused |
| p1 | a yielded view assigned to an outer String | builds |
| p5, p15a | `parse` appends views of `args` to a caller's Array | builds |
| p6 | flag views as Hash keys in a field | builds |
| p8 | a stored `-> Nil` block capturing scalars | builds |
| p13a | an owner storing a view through its own `add` def | refused |
| p14a | `parse` appending to an owner's field directly | builds |
| p14b, p15b | a second parse, keeping a value of the first | builds |
| p14d | `args` built in a loop round | refused in std |
| p9, p13c | a block-taking def whose body is `{% raise %}` | at caller |
| p10-p12 | a def without a block whose body is `{% raise %}` | always |
| p16 | `parse(args)` where only `parse(args, found)` exists | lists it |
| p17a, p17b | a `protected` accessor: other class / program | ok / refused |
| p18 | `puts` of `to_s : String` and of `to_s(String::Builder)` | prints |

## Design

### What the parser keeps

Only views of the text its caller passed, and scalars: the flag and
description texts given to `on`, the names cut from them, the banner
and separators, in the order given. The help is written when asked,
into the caller's `String::Builder` (`help(io)`); `to_s : String` is
that call on the caller's tape, and ris's `puts(value)` prints
`value.to_s` (`src/iyi/io.iyi:365`, p18), so `puts parser` prints it.
The caller's texts must outlive the parser: literals are static; text
built on a shorter scope is refused at `on` by SPEC 3.2, with its
usual safe form (`copy_to(owner)`).

The accepted spellings are unchanged
(`src/std/option_parser.iyi:103-113`, `:278-283`): `--name VALUE`,
`--name=VALUE`, `-n VALUE`, `-nVALUE`, `--color [WHEN]` and `-c[WHEN]`
for a value that may be left out, `-vq` for `-v -q` (a bundle), and
`--` ending the flags. A short and long pair, `on("-v", "--verbose",
…)`, is one registration.

Commands registered the next level's flags in a block, so they are
removed. A name with no dash is refused at `on`, as a malformed flag
is today: "not a flag: deploy; list commands with separator and
dispatch on rest[0]". A program registers every flag up front, lists
its commands with `separator`, and dispatches on `rest[0]`.

### RisFlag and RisOptions

`RisFlag` is a struct holding the registration's index. `RisOptions`
is an owner (SPEC 2.1), declared `found = RisOptions.new` at a named
local. `parse(args, found)` drops what `found` held from an earlier
parse, then appends, in command-line order, each flag given as its
registration index and its value, a view of `args` or `""`. The entry
is always the index, never a key `parse` builds (a bundle's `"-" + c`
is made on its scratch). `parse` appends to `found`'s fields itself:
storing through a `RisOptions` def taking the value is refused (p13a).

`found.has?(flag)` and `found[flag]?` (the last value given) take a
`RisFlag`; before any parse they answer false and nil. `RisOptions` is
a type rather than a caller's Array so that one argument carries the
values and the error lists, and reads are `found[flag]?`, not
`parser.value(found, flag)`. `parse` reaches its fields through a
`protected` accessor, so `ris doc` lists only the readers.

Without `record_errors`, `parse` panics on a bad command line with one
of today's library messages: `unknown flag: --x`, `flag --x takes no
value`, `flag --name needs a value`. After `parser.record_errors`, it
records instead and goes on:

| Command line | `has?` | `[]?` | `invalid` | `missing` |
| --- | --- | --- | --- | --- |
| `-v` (switch) | true | `""` | | |
| `-e x` | true | `"x"` | | |
| `--color` (optional, left out) | true | `""` | | |
| `-e` last (value required) | false | nil | | `-e` |
| `--verbose=x` (switch given a value) | false | nil | `--verbose` | |
| `--nope` | | | `--nope` | |

`invalid` and `missing` answer the flags as typed, read-only by
contract: a program reports them in its own usage line. One list holds
both unknown flags and values given to a switch, as one handler did.

`found`'s fields are made once, by `RisOptions.new`, and refilled with
`clear`: each reserves its own address space, so growth never moves it
(`doc/TAPE_API.md`); the gate checks 0 growth moves. `parse` answers
the operands as an Array of views of `args`, grown in place and
returned (SPEC 1.9). A `found` must not outlive `args`: with
`Program.args` it never does; a shorter-lived `args` is refused
(p14d).

A left-out optional value (`--color`) and an empty one (`--color=`)
both read `""`, as in Crystal's block form.

### The removed forms

A block-taking def can be a stub: its body is only a `{% raise %}`,
reported at the caller's line when called, and Crystal's capture
refusal does not come first (p13c). Each stub's message:

* `on` with a block:

      a ris program reads its flags after parse:
        flag = parser.on("-e EXT", "ending")
        found = RisOptions.new
        parser.parse(Program.args, found)
        found[flag]?

* `invalid_option { }`, `missing_option { }`: call
  `parser.record_errors`, then read `found.invalid` / `found.missing`.

A def without a block cannot be a stub: its `{% raise %}` fires in
every program, called or not (p10-p12). `parse(args)` and `parse` are
removed; a call to them gets the compiler's error at the caller's
line, "wrong number of arguments … Overloads are:", which lists
`parse(args, found)` (p16).

### Naming

AGENTS.md: "An iyi name whose meaning ris changes is renamed". This
draft keeps `OptionParser` as an exception, confirmed by the owner on
2026-11-02: `on`, `parse` and `help` keep their meaning (a flag
parser), what goes is the callbacks; an agent writing Crystal's
`OptionParser` gets the stubs' messages, where a renamed class gives
"undefined constant". The handlers, whose meaning changes, are renamed
(`record_errors`).

## Alternatives

* Let a proc capture a tape value, checked by a root contract.
  Every alias of the proc would have to stay in an owner no older than
  the captured locals, and the proc's parameter would need a checked
  rule that what it is handed outlives what the block stores it in.
  Crystal's form would build unchanged. It is a checker change across
  procs (SPEC 3.1, 3.4) for one library, and calling such a proc is
  refused today as well (p7). Deferred; RisOptions does not block it.
* String lookups, `found.has?("--help")`: Crystal-like, but a
  misspelling only panics when that lookup runs, and `found` must copy
  the registrations. Rejected for handles.
* A yield form, `parser.parse(args) { |flag, value| … }` (p1): no new
  type. Every flag's text is written twice and a misspelled `when` is
  silent. Rejected.
* `-> Nil` blocks for switches (p8) beside `found` for values: two ways
  to read a flag. Rejected.
* A plain caller Array for `found` (p15a), read through
  `parser.value(found, flag)`: works, but the error lists need a
  second and third argument. Rejected for RisOptions.
* Rename the class (`RisOptionParser`): rejected, see Naming.
* A new annotation carrying the hint into the compiler's capture
  refusal: a compiler feature for one library, and p7's refusal would
  still follow. Rejected for the stubs.

## Non-goals

* No change to the proc capture rule, the checker or any SPEC rule.
* No nested commands, no repeated-value list (`-I a -I b`) and no typed
  values (`found.int?`): `[]?` gives the last value, `to_i` reads it.

## Risks

* A shorter-lived `args` is refused at the append inside the library
  (p14d), not at the caller, with a generic message. Accepted: every
  trial program passes `Program.args`; the library's doc comment names
  it, and TODO.md records the checker gap: the refusal belongs at the
  caller's `parse` line.
* `parse` drops what `found` held. A value read from the first parse
  stays valid (p14b); reading `found` again gives the second. The doc
  comment states it.
* `RisOptions` and `RisFlag` are new Ris* types that iyi does not have
  (AGENTS.md naming). As an owner, `RisOptions` cannot be a temporary
  (SPEC 2.1); the refusal names the declared form the example uses.
* The API leaves iyi's: UPSTREAM.md records it for the next merge.
* A stub reports only when called. Accepted: code that never calls a
  removed form needs no message.

## Implementation Plan

### Phase 1: the library and its gates (one commit)

1. `src/std/option_parser.iyi`. Fields and public defs:

       struct RisFlag            # getter index : Int32
       class RisOptions          # owner (SPEC 2.1)
         @given : Array({Int32, String})   # index, value view
         @invalid : Array(String)
         @missing : Array(String)
         def has?(flag : RisFlag) : Bool
         def []?(flag : RisFlag) : String?
         def invalid : Array(String)        # read-only by contract
         def missing : Array(String)
         protected def given : Array({Int32, String})
       class OptionParser
         @long, @short : Hash(String, {Value, Int32})  # keys view `on`
         @help : Array({String, String, String})
                 # flag, second spelling or "", description;
                 # a separator is {text, "", ""} with no dash
         @banner : String?
         @record : Bool
         def on(flag, description) : RisFlag
         def on(short, long, description) : RisFlag
         def record_errors : Nil
         def banner=(text : String) : Nil
         def banner : String?
         def separator(text : String) : Nil
         def parse(args : Array(String), found : RisOptions)
           : Array(String)
         def help(io : String::Builder) : Nil
         def help : String
         def to_s : String

   `protected` reaches `given` from `OptionParser` and hides it from a
   program (p17a, p17b). The help text stays byte-identical to today's:
   banner default `options:`, lines `  FLAG  DESC` and
   `  SHORT, LONG  DESC`. The run-time messages stay as today, prefixed
   `option:`: `not a flag: -`, `-v and --verbose differ on the value:
   …`, and the three parse panics; a dashless name gets
   `option: not a flag: deploy; list commands with separator and
   dispatch on rest[0]`. Rewrite the header comment (lines 1-33): the
   example in Change; pass `Program.args`; `found` must not outlive
   `args`; `parse` drops what `found` held; `invalid` / `missing` are
   read-only; a `RisFlag` belongs to the parser that made it.
2. Stubs, exact text, one per block-taking def (both `on` forms share
   it):
   * `on`: `a ris program reads its flags after parse: flag =
     parser.on("-e EXT", "ending"); found = RisOptions.new;
     parser.parse(Program.args, found); found[flag]?` (the four
     statements one per line in the source string).
   * `invalid_option`, `missing_option`: `a ris program records bad
     flags: parser.record_errors, then read found.invalid and
     found.missing after parse`.
3. `test/ris/option_parser.ri` (module `test/option_parser`), with its
   `args` a literal Array declared beside `found` (p14d). Cases, all
   from the bench or the table: `-v`/`--verbose` pairs; `--name VALUE`,
   `--name=VALUE`, `--out=FILE` and `-oFILE` registrations; `-nVALUE`;
   bundles `-vq`, `-qvp8080`; `-vx` and `-q=1` invalid; `-é` and `-ö`;
   `--color [WHEN]` left out, given, and before `-v` (not taken);
   `-z[N]`; `--`; each row of the table with `record_errors`; a second
   parse on the same `found`; `rest`; the help after `banner=` and
   `separator`, compared whole. It prints one line per case and
   `PASS: option_parser`. check.sh block, as text_grow's:
   `RIS_TAPE_STATS=1 "$RIS" run test/ris/option_parser.ri`, exit 0, a
   literal `want=` of the case lines, and the needles
   `0 growth moves off the tape's end (0 bytes copied)` and
   `0 side regions (0 transfer bytes copied)`.
4. `test/ris/option_parser_panics.ri CASE`: one panic per case name,
   run by a check.sh loop with `-- CASE`, each needing a nonzero exit
   and its message on stderr: `dash` (`not a flag: -`), `dashless`,
   `pair` (differ on the value), `unknown` (`unknown flag: --x`),
   `novalue` (`flag --verbose takes no value`), `missing`
   (`flag --name needs a value`).
5. `test/ris/refused/option_parser_block.ri`,
   `option_parser_pair_block.ri`, `option_parser_handler_block.ri`,
   and `option_parser_parse_one.ri` (`parse(args)`): each checked like
   tape_block_handler_store, by two greps: the message
   (`reads its flags after parse`, `records bad flags`,
   `Overloads are:`) and `option_parser_NAME.ri:LINE:` of the call.
6. Remove `bench/std_option_parser_exercise.iyi` and `.sh`. Its release
   build and mutation proofs go with it: the `want=` block fails on
   any changed answer, as the other std gates do.

Gate: `bin/minitest-check check` passes (`std_text_plain` included).

### Phase 2: the trial program and documents (one commit)

7. `samples/ris/trial/ls.ri`: `-l` and `-e EXT` through `found`, the
   directory from `rest[0]`; an unknown flag now panics (it was taken
   as the directory). `run.sh`'s `args_ls` becomes `-l -e .txt data`,
   and `expected/ls.txt` is rewritten from a checked run.
8. Remove `samples/ris/trial/blocked/option_parser_string.ri` and its
   README line. TODO.md: drop "`OptionParser` String option" from
   Order of work (item 2) and the item at its list; add the p14d gap to
   "Checker holes found on the way". LEARN.md section 2, the
   `Program.args` bullet: one sentence and the four-line form.
   UPSTREAM.md, Stays in ris: OptionParser without blocks, RisOptions,
   RisFlag.

Gate: `samples/ris/trial/run.sh` and `bin/minitest-check check`.

9. Run ris-bench's goose-evals.sh: it has no flag-parsing eval, so the
   commit body records its four port lines unchanged (AGENTS.md, Tape
   first).
