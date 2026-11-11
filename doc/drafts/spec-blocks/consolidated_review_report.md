# EGM Consolidated Review: spec blocks (changed sections)

**Verdict:** REVISE (2 blockers, 9 majors, 13 minors)

**Target:** `doc/drafts/spec-blocks/spec-blocks.md`, changed sections only:
D16-D18, D6 and D12 edits, 4.2-4.5, 5.5, 5.7, 5.8 last paragraph,
5.11 end, 5.16, section 6 step 4, additions in 7 and 9. D1-D18 are the
user's decisions and are not reopened; findings concern how the draft
states them.

## Reviewer status

| Reviewer | Status |
| --- | --- |
| `egm-design` | completed |
| `egm-implementation-readiness` | completed |
| `egm-zoom-out` | completed |
| `egm-codebase-details` | completed |

## Blockers

### B-1 The two meanings of the module name do not survive lowering

- Section: 5.7 (two meanings of `demo`), D17, 4.4, 4.5.
- Problem: 5.7 makes bare `demo` a RisProgram as a call argument and
  a RisRun elsewhere; D17 does not state this rule. Lowering runs in
  the parser before typing (parser.cr:430-499). The `=~` rewrite
  passes its left side straight into `RisSpecRun.match`
  (parser.cr:477-481), so `demo =~ %r{..}` makes `demo` an argument,
  hence the program. `demo` is a generated def, so `demo.start` parses
  as "run, then `.start` on the run". `assert_eq(demo, ..)`, `p demo`
  and `x = demo; get(x, "/")` are ambiguous too. (all four reviewers)
- Fix: give the program one spelling (e.g. `demo.program`, through
  which `.start` also goes) and keep bare `demo` always a run; or state
  the syntactic rule in D17, say the parser rewrites `demo.start` and
  argument `demo` to a RisProgram before lowering, and make the `=~`
  rewrite bind its left side to a temporary as comparisons do
  (parser.cr:469). Update 4.4, 5.16 and the section 9 web/spec item.

### B-2 "The block's timeout" does not exist

- Section: 5.7, D16, D17, 5.8.
- Problem: `demo(...)` and `wait_for` rely on a per-block timeout, but
  the limit is per test binary: on expiry test.cr:444-454 kills the
  tree and marks the whole file hung; `RisSpecRun.block`
  (testing.iyi:260-285) has no timer. (codebase-details)
- Fix: state that the limit is per file today and becomes per block
  in step 4, adding it to step 4's scope and gate; or drop the reliance.

## Majors

### M-1 Stale `demo.run` / `run` references

- Section: 5.11 end, section 6 step 7 gate, section 10 M-9.
- Problem: "With `run` in v1 (D12)" and "1.1 covered by `demo.run`
  (D12)" name the old handle; 5.11 offers both the todo form and a
  real check, so what init writes is unclear. (all four)
- Fix: since step 7 follows step 4, init writes
  `demo == "hello from demo\n"` (4.5); gate reads "covered by a `demo`
  block"; drop the todo variant.

### M-2 Children and `tmp` outlive a timeout kill or crash

- Section: 5.7, 5.8, step 4 gate.
- Problem: cleanup is "at block end", which never runs when the
  harness SIGKILLs the test binary or wasm32 panics; `demo.start`
  children, hung `demo(...)` runs and `tmp` remain. The pgrep gate
  covers only the clean path. (design, impl-readiness)
- Fix: run each test binary in its own process group and kill the
  group; harness removes a per-run temp root. Gate: a block hanging
  in `demo.start` is killed and leaves no process or tmp dir.

### M-3 Import scope inside the spec section

- Section: 4.4, 5.4, 5.6, 5.16.
- Problem: `post(blog, ..)` appears above `import web/spec::*`; no
  text says a test-only import covers blocks above it. If not, the
  example fails and 5.16's hint suggests an import already present.
  (design, impl-readiness)
- Fix: state that test-only imports apply to the whole section, or
  move the import above its first use and say imports apply below.

### M-4 Where the runtime lives and how it is imported

- Section: 5.7 vs 5.2, step 4 gate.
- Problem: 5.7 puts RisTmp, RisRun, RisProcess, RisProgram in
  std/ris_spec "which only `ris build --spec` imports"; RisSpecRun is
  in the prelude (testing.iyi:213) and `ris_lower_spec` injects no
  import (parser.cr:430-437). Nothing says how `tmp` and `free_port`
  reach a block. (all four)
- Fix: say `ris_lower_spec` adds `import std/ris_spec` to kept nodes,
  or place the types beside RisSpecRun and rely on dead-code removal.
  Name `free_port`'s home; make the step 4 symbol check match.

### M-5 `RisRun =~ regex` failures label the wrong side

- Section: 5.7, 4.4, 4.5.
- Problem: `RisSpecRun.match` picks the pattern by
  `left.is_a?(String)` (testing.iyi:250); a RisRun on the left prints
  as the pattern. The type check (parser.cr:463) also needs RisRun's
  `=~` and `==(String)`, which 5.7 does not declare. (codebase-details)
- Fix: decide by `is_a?(Regex)` in step 4; declare RisRun `=~ :
  Int32?` and `==(String) : Bool` in 5.7.

### M-6 Exit status and timed waits have no named primitive

- Section: 5.7, step 4.
- Problem: std/process reports exit code and signal separately
  (process.iyi:163, :268), not "128 + N"; it has `terminate`, `kill`,
  `signal` (process.iyi:517-533) but no timed wait, which `stop`
  (SIGTERM, 2 s, SIGKILL) and `wait_for(regex, timeout)` need.
  (codebase-details)
- Fix: define status as `signal > 0 ? 128 + signal : exit_code`;
  name the timed-wait mechanism (task plus timer, or a new std
  helper) and add it to step 4.

### M-7 Pipe draining and wasm32 behaviour unspecified

- Section: 5.7, 5.8.
- Problem: `stdout`/`stderr` "so far" and `wait_for` need something
  to drain both pipes, or a chatty child blocks; 5.8 says wasm32 has
  no tasks but not what `tmp`, `demo`, `start` do there.
  (impl-readiness)
- Fix: state the reader (e.g. one task per stream appending to a
  builder, reusing process.iyi's child output state) and the wasm32
  rule (e.g. `demo`, `start`, `free_port` are compile errors; `tmp`
  works).

### M-8 Child environment only partly specified

- Section: 5.7.
- Problem: not said whether the parent environment is inherited
  (PATH, `ENV["PORT"]` in blog.ri); `RIS_SPEC_JSON` and
  `RIS_SPEC_PROGRAM` leak into the child and change a ris runner
  under test. (design, impl-readiness)
- Fix: "parent environment minus `RIS_SPEC_*`, then HOME and TMPDIR,
  then *env*", same for `start`; process.iyi's nil env values unset.

### M-9 5.16 hint misses the draft's own example

- Section: 5.16, 4.4, steps 4 and 6.
- Problem: the hint fires only for a package the file imports
  directly; blog.ri imports `site`, not `web`, so a missing
  `import web/spec::*` gets no hint. Step 4 says the hint moves to
  step 6, but step 6 does not list it. (design, zoom-out)
- Fix: widen to the import closure or say blog.ri gets no hint; add
  the chosen case to step 6's text and gate.

## Minors

- m-1 D12: writes `demo(args, stdin:)`; copy D17's
  `demo(*args, stdin = "", env = {})` or just cite D17.
- m-2 D17 vs 5.7: signatures differ (`start(args, env:)` vs
  `start(args = [] of String, ...)`); say 5.7 is authoritative and cut
  D17's SIGTERM/2 s/method list to a pointer to 5.7.
- m-3 5.16/D18: refusing any import whose last segment is `spec`
  hits ordinary modules (`billing/spec`); limit to package roots in
  `lib/`/`mods/` or reserve the name with its own error.
- m-4 5.7/section 9: `free_port` race; require web/spec to retry
  `start` once on a bind failure.
- m-5 5.7 opening, D17: "core knows no port" yet defines
  `free_port`; say "no port wait and no protocol".
- m-6 4.4 last paragraph: reads as if the core sets `PORT`; write
  `web/spec calls blog.start(env: {"PORT" => free_port.to_s})`.
- m-7 5.7: add that std/ris_spec is a thin layer over std/process
  and std/dir, so no second process or temp-dir code is written.
- m-8 5.8 CLI paragraph: "run_one_test shells out to `build FILE -o`
  (test.cr:363)" is stale; it is test.cr:400 and already uses
  `build --spec` with `RIS_SPEC_JSON=1` (test.cr:417, :424). Only
  `RIS_SPEC_PROGRAM` is new.
- m-9 4.6: `ris spec` lists 3.6 at `blog.ri:10`; in 4.4 that is the
  import, `spec 3.6` is line 12.
- m-10 5.7 vs 5.5/D6: the header-less module name (file base name)
  is stated only in 5.7; state it once in D6 or 5.5.
- m-11 Step 4 gate: add `tmp` removal after a panic and a
  `free_port` case.
- m-12 Section 3: the Goals line exceeds 80 columns; rewrap.
- m-13 5.7: an explicit note that the parser, not the typer, picks
  the program vs run meaning (folds into B-1 if the rule is kept).
