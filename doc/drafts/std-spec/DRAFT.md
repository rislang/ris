# Draft: the std specification lives in its modules

Status: draft, EGM reviewed 2026-11-13 (consolidated_review_report.md:
0 Blocker, 7 Major, 4 Minor); every Major is answered in section 7.
No SPEC.md or code change yet.

## 1. Problem and decided shape

src/std/SPEC.md (committed in 2739b82d5, 4488 lines) holds 967 clauses
for 120 std modules, `* json.3 text (test/cli/std_json_exercise.iyi)`. 137 lines say
`<!-- todo: Needs proof -->`, 27 more carry another todo marker. No tool
reads the file: a clause and its proof drift apart unseen, and an agent
editing json.iyi never sees json's promises.

Decided by the user, done before 0.1.0:

* A module's clauses live in the module's own file, next to the `spec`
  blocks that prove them.
* src/std/SPEC.md stays short and general: the rules every std module
  keeps and the list of modules.

## 2. What exists today

All in src/compiler/iyi/command/spec_clauses.cr unless named.

* Root: the nearest dir with ris.mod or iyi.mod, else the current dir if
  it holds a spec (128-138). ris's repo has no manifest, so its root is
  the repo top and src/std/ is inside it.
* One spec source: SPEC.md or spec/*.md, both is an error (144-157).
  No other file is read; src/std/SPEC.md is never read by any tool.
* A clause is `* N.M text` under `## N. Title`, N equal to the chapter,
  numbers unique, continuation lines indented (159-226). Ids are digits
  only: `spec_number?` (237-241) refuses `json.3`.
* Version: first 8 hex of SHA-256 of whitespace-collapsed text (243).
* Todo marker: `  <!-- todo: reason -->` after the clause text, at most
  80 columns, one per clause (175-185).
* Blocks: every `.ri`/`.iyi` under the root via `project_walk`
  (project_walk.cr:14-27, skips lib/, mods/, dot dirs, .ris-fixtures),
  head `spec N.M  # label` (305-346). So src/std blocks already count.
* The parser accepts `spec 1.2.3` (parser.cr:270, `\d+(?:\.\d+)+`) but
  the command scanner only N.M (339): no module ids either way. A build
  refuses a block naming no root clause (parser.cr:905-915; clause set
  from spec_clauses.cr:94-110).
* Old tags: a test under test/ names clauses in its leading `#` block,
  `# spec: 1.3@a4f20c19`, or prose `SPEC 1.3` (247-301, 442-461).
* .spec.lock: one file at the root, `N.M HASH` lines (364-389); `ack`
  writes it and drops lines for vanished clauses; `ack N` takes a whole
  chapter (702-758).
* `ris check spec` (791-887, wired in check_suite.cr:92,128): tag/block
  naming no clause, stale label, lock line for no clause, unreviewed
  clause, clause version missing from CHANGELOG.md (870-873), clause
  with no proof. Block 8.1 also needs `# standard:` in the header
  (821-828).
* src/std today: 20+ modules end in `spec 8.1` blocks (root SPEC 8.1,
  "follows the standard its header names"). The std_*_exercise tests
  are mostly untagged; tagged ones name root clauses (`5.1`, `1.1`),
  not module clauses. Root .spec.lock has 43 lines.
* Gates: test/cli/spec_verb.py, spec_marker.sh/.py,
  spec_blocks_{grammar,imports,init,lock,old_test,program,run}.sh.
* Root SPEC 6.7-6.9 (SPEC.md:259-285) state all of the above.

## 3. Proposed form

Smallest change: module clauses join the root's one clause set. Same
version hash, same .spec.lock, same `ris check spec`; only the id and
where the text is read from are new.

### 3.1 Id

`MODULE.N`. Root clauses keep `N.M`.

* MODULE is the file's path under ROOT/src without `.ri` or `.iyi`, a
  leading `std/` dropped: src/std/json.iyi is `json`, src/std/eiy/x.iyi
  is `eiy/x`, a package's src/route.ri is `route`. Each segment matches
  `[a-z_][a-z0-9_]*`; segments join with `/`.
* Two files with one MODULE (json.ri beside json.iyi, src/json.iyi
  beside src/std/json.iyi) fail: "two files are module json: A, B".
* Files are found by `project_walk` under ROOT/src, with its exclusions
  (symlinks, lib/, mods/, dot dirs, .ris-fixtures). A file outside
  ROOT/src holds no clauses; a `spec json.3` block there is a further
  proof of the clause.
* N is a positive integer without leading zeros; `json.0` is refused.
* A number is never reused. The tool refuses two live clauses with one
  id; it keeps no history, so reuse of a removed number is a review
  rule: `ris spec ack` prints "removed: json.4" for each lock line it
  drops, and the reviewer checks a new clause is numbered past the
  module's highest ever (git log -S 'spec json.' shows it).
* Text cites a std clause as `std json.3`.

### 3.2 A clause in its module

The clause is a comment directly above the block that owns it, in the
spec section at the end of the file. Every clause has exactly one owning
block; its first line is `# MODULE.N text`, continuation lines
`#   text`. A todo clause owns a block holding one `todo "reason"`
line per reason (log.9 has three markers today, so three lines); each
marker's reason moves there byte for byte, `"` and `\` escaped. The
owning block takes no `# label`: the text is right above it, and
`ris check --fix` leaves an owning block's head alone (running it twice
changes nothing).

The clause comment is the unbroken run of `#` lines that starts at
`# MODULE.N ` and ends on the line before `spec MODULE.N`. A line
`# MODULE.N ` with this file's MODULE and no such block right after the
run is an orphan and fails; a second owner of one id fails as a
duplicate. Comments naming another file's module are prose.

The old file's trailing proof citation, `(test/cli/std_json_exercise.iyi)`,
is not part of the comment: the proof is the block below.

Worked example, end of src/std/json.iyi:

```
# json.1 Parsing maps null to Nil, booleans to Bool, fitting integer
#   literals to Int64, other numbers to finite Float64, strings to
#   decoded String, arrays to Any elements and objects to ordered
#   RisJsonFields. Integer -0 becomes zero.
spec json.1
  JSON.parse("null").as_nil?
  JSON.parse("-0").as_i64 == 0
  JSON.parse("1.5").as_f == 1.5
end

# json.12 Document nodes use a caller-tape RisTree view; unescaped keys
#   and strings view the input, while escaped text views the document's
#   decoded buffer. Any and RisJsonFields retain those roots, and text
#   results use SPEC 1.5; retention requires SPEC 1.7.
spec json.12
  todo "Needs proof"
end
```

Further blocks may name `json.1` elsewhere (in json.iyi or another
module); they keep the usual `# label` rule.

### 3.3 Tools

* Clauses: `spec_clauses` also reads every `.iyi` under ROOT/src/std
  (and, later, any package's src/), taking `# MODULE.N` comments that
  sit directly above `spec MODULE.N`. MODULE must match the file:
  `json.3` in yaml.iyi fails with "move it to src/std/json.iyi".
  Duplicates are refused as for N.M (reuse: see 3.1).
* The parser lets a block end in several `todo` lines (today: one, the
  last line); nothing but `todo` lines may follow the first.
* A block's todo reasons are kept (a list, not a Bool): `ris spec todo`
  lists them beside marker reasons, `ris spec --json` gives
  `"todo": ["reason", ...]` for a clause.
* `spec_number?`, `spec_block_head`, the parser regex, lock and tag
  parsers and `spec_version_tokens` accept `MODULE.N`.
* `ris spec`: lists root clauses, then module clauses by module.
  `ris spec json` shows a module, `ris spec json.3` one clause (with
  file:line). `ris spec ack json` / `ack json.3` as for chapters.
* `ris check spec`: unchanged rules apply to module clauses, plus: a
  `# MODULE.N` comment with no block below it fails; a module clause's
  version needs no CHANGELOG.md entry (git and .spec.lock record it;
  decision 6.2).
* .spec.lock: root file, lines `json.3 1a2b3c4d` after the N.M lines,
  sorted by module then N.

### 3.4 The short src/std/SPEC.md

A plain document, no clauses of its own (the root spec keeps the rules,
see 4): what every std module keeps, citing SPEC clauses (borrow input
as String, results on the caller's tape, no raw pointers in an API, ids
never change, a module's clauses are in its file), how to read them
(`ris spec json`), and the module list with one line each. Under 150
lines.

### 3.5 Rejected

* One spec/std-json.md per module: still apart from the proof; drifts.
* Keep the big file and parse it: the decided shape forbids it.
* Clause text inside the block (`spec json.3 "text"`): blocks run as
  code; text in a string confuses the parser and the label rule.
* `@[Spec("…")]` annotations: not on blocks; long text in annotations.
* A .spec.lock per module: 120 more files, no gain over sorted lines.
* Numbering std clauses into root chapters (8.12): loses the module in
  the id and renumbers on every move.

## 4. Root SPEC.md and AGENTS.md changes

* SPEC 6.7: a spec is SPEC.md or spec/*.md plus module clauses
  (`# MODULE.N` above `spec MODULE.N` in src/std); the id form.
* SPEC 6.8: the two new failures (orphan comment, MODULE mismatch) and
  the CHANGELOG exemption.
* SPEC 8.2 (new): a std module's promises are its clauses in its file;
  numbers never change; src/std/SPEC.md lists the modules and shared
  rules. The four shared rules cite existing clauses (1.5, 1.9, ...).
* AGENTS.md "Tape first", the spec bullet: "a std clause sits as a
  `# json.3` comment above its block in its module". No other line.

## 5. Migration

Done: src/std/SPEC.md is committed as is (2739b82d5).

### 5.1 Order of commits

1. Tools (3.3) with gates in test/cli on a scratch project: ok, todo
   with two reasons, mismatch, orphan comment, duplicate owner, two
   files one module, a non-std src/route.ri, a nested src/a/b.iyi, both
   extensions, a clause under lib/ (ignored), ack and its "removed:"
   line, lock order, --fix twice. Root SPEC 6.7, 6.8, new 8.2, AGENTS.md
   and CHANGELOG.md land in this commit. `ris check` green.
2. Baseline: a script (scratchpad, not committed; one script, run per
   module) reads src/std/SPEC.md and writes for each of the 967 clauses
   its id, its text with the trailing `(test/...)` citation removed,
   the version of that text, and every todo reason in order. The same
   script later reads `ris spec --json` and prints the difference.
3. One commit per module, alphabetical, in this order:
   a. append the clause comments and owning blocks to MODULE.iyi and
      delete the module's section from src/std/SPEC.md;
   b. move the exercise's checks into the blocks (5.2, 5.3);
   c. compare the module with the baseline: same ids, versions and todo
      reasons; the commit body says "baseline: N clauses, no diff";
   d. `ris spec ack MODULE` after reading the blocks;
   e. remove what 5.2 allows; `ris check` green; commit.
   Between module commits src/std/SPEC.md holds the modules not moved
   yet; no tool reads it, so every checkpoint is green.
4. Last: the whole-baseline comparison (967, no diff) in the commit
   body, and src/std/SPEC.md replaced by the short form (3.4).

### 5.2 What an exercise's shell script keeps

A std_NAME_exercise.sh often does more than run the program: it reads
the program's output (sentinels, a corpus), compares with an outside
oracle (Python's json, libxml2), builds with --release, and builds
programs that must be refused. Before a module moves, list for it: the
program's checks, the script's assertions, fixtures, who reads the
program's output, and the build modes. Then:

* A check inside the program moves into a block.
* Output that the script reads stays: the program shrinks to a producer
  with no checks of its own, and the script keeps consuming it.
* Refusal programs, oracle comparisons and mutation proofs stay in the
  script. Its plain and --release runs of the checks become runs of the
  module's spec blocks in both modes.
* The program and its script are removed only when the list shows
  nothing left for them; test/ris/check.sh loses the line then.

### 5.3 Counting checks

One check is one place a test can fail, counted in the source text by
the baseline script, the same way before and after:

* in an exercise: each call of its assertion helper and each direct
  failure site (a `fail`/exit-nonzero line outside the helper);
* in a spec block: each top-level expression line (a block fails when
  one is false) and each helper call inside it;
* a check in a loop or helper body counts once, however often it runs;
  one assertion with several `&&` conditions counts once;
* in a shell script: each line that sets the failing status.

Per module the count after (blocks + remaining program + script) is at
least the count before; the commit body gives both numbers. The mapping
of each old check to its block is a scratch worksheet, not committed.

## 6. Decided (user, 2026-11-13)

1. The 837 clauses proven by test/cli/std_*_exercise: each proof moves
   into its `spec MODULE.N` block before 0.1.0, module by module, as in
   the rispacks ports. An exercise program is removed when all its
   checks have moved; the number of checks per module must not go down
   (counted before and after). No `# spec:` tags, no todo placeholders
   for a clause that has a test.
2. CHANGELOG.md: module clauses are exempt; git and .spec.lock record
   their versions.
3. The clause comment sits directly above its owning block.
4. The mechanism is not std-specific (any `src/` under a root), but
   only std moves now; rispacks keep their SPEC.md.

## 7. Answers to the EGM review (2026-11-13)

* M1 discovery and identity: 3.1 defines MODULE for std, nested and
  package files, the walk and its exclusions, and collisions; 3.2 the
  comment's bounds and the orphan rule; 5.1 step 1 lists the fixtures.
* M2 number reuse: the tool refuses live duplicates and non-positive
  numbers only; reuse of a removed number is a review rule helped by
  ack's "removed:" line (3.1). No history file is added.
* M3 hash baseline: the citation is dropped; the baseline is the old
  text without it, hashed by the same rule on both sides (3.2, 5.1.2).
  Module clauses are not in .spec.lock yet, so no acked version changes.
* M4 todo reasons: one `todo` line per reason, kept as a list, shown by
  `ris spec todo` and --json; the baseline holds all reasons (3.2, 3.3).
* M5 shell coverage: 5.2. This narrows decision 6.1's "removed when all
  its checks have moved" to "and nothing reads its output".
* M6 checkpoints: 5.1 step 3 gives the per-module order with ack before
  the green check; step 1 says when SPEC and AGENTS land.
* M7 counting: 5.3.
* Minor N1-N4: fixed in place (6.2 reference, --fix on owning blocks,
  one script, the baseline commit is done).
