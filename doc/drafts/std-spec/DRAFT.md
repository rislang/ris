# Draft: the std specification lives in its modules

Status: draft, before EGM review. No SPEC.md or code change yet.

## 1. Problem and decided shape

src/std/SPEC.md (untracked, 4488 lines) holds 967 clauses for 120 std
modules, `* json.3 text (test/cli/std_json_exercise.iyi)`. 137 lines say
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

`MODULE.N`: MODULE is the module's path under src/std without `.iyi`
(all 120 are top-level files today: `json`, `crypto`); N a positive
integer, never reused. Root clauses keep `N.M`. Text cites it as
`std json.3`.

### 3.2 A clause in its module

The clause is a comment directly above the block that owns it, in the
spec section at the end of the file. Every clause has exactly one owning
block; its first line is `# MODULE.N text`, continuation lines
`#   text`. A todo clause owns a block holding `todo "reason"` (the
marker's reason moves there). The owning block takes no `# label`: the
text is right above it.

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
  Duplicates and gaps-reused are refused as for N.M.
* `spec_number?`, `spec_block_head`, the parser regex, lock and tag
  parsers and `spec_version_tokens` accept `MODULE.N`.
* `ris spec`: lists root clauses, then module clauses by module.
  `ris spec json` shows a module, `ris spec json.3` one clause (with
  file:line). `ris spec ack json` / `ack json.3` as for chapters.
* `ris check spec`: unchanged rules apply to module clauses, plus: a
  `# MODULE.N` comment with no block below it fails; a module clause's
  version needs no CHANGELOG.md entry (git and .spec.lock record it;
  see question 2).
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

1. Commit src/std/SPEC.md as is first, so the source is in git.
2. Land the tool change (3.3) with gates in test/cli: a scratch project
   with module clauses (ok, todo, mismatch, orphan comment, ack, lock).
3. A one-off script (scratchpad, not committed) per module, alphabetical:
   append the clause comments and blocks to src/std/MODULE.iyi. A clause
   citing a test gets a block with `todo "proof in test/cli/<file>"`
   unless question 1 says otherwise; a marker reason becomes the
   block's todo text. Reflow to 80 columns keeps the version.
4. Gate that none was lost: the script dumps id and version of all 967
   from the old file; `ris spec --json` after must list the same 967
   ids with the same versions and the same todo reasons. Put the diff
   (empty) result in the commit body; then `ris spec ack` per module.
5. Replace src/std/SPEC.md with the short form (3.4), `ris check` green.

The exercise tests stay; they keep running in `ris check`. They become
proofs either by tags (question 1 b) or by moving their checks into
blocks module by module after 0.1.0.

## 6. Open questions

1. How do the 837 clauses proven by test/cli/std_*_exercise count?
   a) block with `todo "proof in test/cli/…"`: honest, 837 todos;
   b) tag the exercise: `# spec: json.1, json.2, …` (old mechanism,
      counts as proof now, legacy per AGENTS.md);
   c) move each proof into its block before 0.1.0 (much work).
   Recommendation: b now, c module by module later.
2. CHANGELOG.md for module clauses: a) exempt (git + lock suffice);
   b) one migration entry listing all 967 `id@ver`, then per change.
   Recommendation: a; 967 tokens are noise and std changes often.
3. Should the comment sit above its block (as proposed) or in the
   module header? Header: read first by an agent, far from the proof.
   Recommendation: above the block (the decided "next to the proof").
4. Do packages outside std (rispacks) get module clauses too?
   a) yes, any `src/` under a root; b) std only for now.
   Recommendation: a, it is the same code path, gated once.
