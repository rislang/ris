# Comprehension Report: Stage 6

**Target:** `doc/drafts/option-parser/option-parser.md` (second draft;
FeatureRange 1-177, DetailedRange 178-198)

## What this proposes

Make `std/option_parser` work in ris programs by adding a "register,
parse, then read" form. The program registers flags with `on(...)`
calls that take no block, makes a named `found = RisOptions.new`, and
calls `parser.parse(args, found)`. `parse` fills `found` with views of
`args` and of the flag texts and returns the operands. The program then
asks `found.has?(flag)` and `found[flag]?`; both accept either spelling
of a flag and raise on a name the parser never registered. Unknown or
valueless flags go into `found.invalid` / `found.missing` only if the
program calls `invalid_option` / `missing_option` without a block.
Otherwise `parse` panics. In a ris build, every block-taking def (`on`,
`invalid_option`, `missing_option`) hits a `{% raise %}` under
`flag?(:ris_no_gc)`, reported at the caller's line, that shows the new
form. The parser also stops building help strings when a flag is
registered and formats help when asked. No SPEC or compiler change.

## How the existing system works, per this document

`OptionParser` lives in `src/std/option_parser.iyi`, a file shared with
iyi. `on(flag, desc) { |v| … }` stores the block as a `String -> Nil`
proc and adds a help line built on `on`'s scratch to a field.
`parse(args)` walks the arguments, calls the stored procs, panics on
unknown or valueless flags unless handler blocks were given, and
returns the operands. In ris, three things refuse this: the caller's
capturing blocks (proc capture), the library's own help store (SPEC
1.1/3.6), and calling a stored proc with a view (probe p7). So no ris
program can use `OptionParser` today, and no ris gate builds it.

## Findings

### No-block `invalid_option` / `missing_option` never shown - Major
Lines 31-34, 97-100, 105-106: no signature or call example.

### `parse(args)` without `found` in a ris program unstated - Major
Lines 114-115, plan 184-185: allowed, ignoring no-block flags, or
refused? A silent-default trap.

### A command name without a block is unclear - Major
Lines 159-162: is `on("deploy", "desc")` accepted (help line, left in
`rest`) or refused?

### Probes p5-p9 cited without a location - Major
They are in the untracked `samples/ris/probe_op/`; p1-p4 unmentioned.

### `flag?(:ris_no_gc)` versus "a ris program" defined late - Major
Lines 126, 174-175: whether every entry point sets it, and that iyi
never does, is unstated; "the gate" is unnamed.

### Nits
* L28-29 "names this form": unclear referent.
* L99 vs L108: "panics" and "raise" both used.
* L92-97: the layout of `found`, and its reset by `parse`, unstated.
* L120, plan: optional-value syntax, "glued values", "bundles" unshown.
* Terms: scratch, root contract, the agent, minitest, iyi vs ris.
* L172-173: half-stated risk entry.
* Plan step 5: which README.

## Resolution (author)

Checking the `ris_no_gc` finding changed the design: the compiler adds
`ris_no_gc` to every program (compiler.cr:2834), and `bin/iyi` is the
same binary as `bin/ris`. Run on minitest at 6173b7918,
`bench/std_option_parser_exercise.sh` fails at its first block ("this
block becomes a proc … `name : String`"). There is no iyi build that
keeps the block form, so the third draft:

* removes every block form and leaves an unconditional `{% raise %}`
  refusal in its place (no flag condition); the bench is ported to the
  ris gate and removed;
* refuses `parse(args)` / `parse` the same way, naming
  `parse(args, found)`;
* defines a dashless no-block `on` as a help line, its name left in
  `rest`;
* shows the opt-in calls; uses "panic" (`raise`, SPEC 4.1) throughout;
* moves the probes to `doc/drafts/option-parser/probes/` and lists
  them; defines the terms; drops the half-stated risk; names the README.
