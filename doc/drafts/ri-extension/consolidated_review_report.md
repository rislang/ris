# EGM consolidated review: ri-extension

Date: 2026-11-13.
Target: doc/drafts/ri-extension/DRAFT.md, 181 lines, unchanged.
Status: complete. Revise the draft before implementation.
Deduplicated findings: 1 Blocker, 9 Major, 3 Minor.

## Run configuration

Requested mode: consolidated report, all five rubrics, no stage stops.
Semantic split: section 5, Migration, at line 135.
FeatureRange: 1-134. DetailedRange: 135-181.
Default reading list: no extra context beyond draft references.
Stage 8 additionally received the three earlier reports, as required.
Section 1 decisions remain fixed. Findings address execution risks and
unanswered section 6 questions, not whether to do the decided migration.
No remediation round was run: the user's report-only instruction
overrides repair gates. Findings remain recorded, not accepted risks.
No questions, commits, source changes or full test suite were run.

EGM root: /home/priit/.claude/plugins/marketplaces/egm.
The orchestrator read docs/codex.md and skills/egm-review/SKILL.md,
plus the review-loop instructions. Direct dispatch used native agents
with fork_turns set to none for each reviewer. Reviewers were read-only;
the parent wrote reports and ran the small probes recorded below.
The five stages ran in order. No same-context reviewer was simulated.

## Checked answers to section 6

### Internal names appear on public surfaces

Checked, parent probes using the checkout's ./bin/ris:

`ris doc IO` prints:

```text
alias IO = IyiIO
class IyiIO
```

`ris doc IyiAtomic` prints `struct IyiAtomic` and its methods.
Building a scratch file containing `IyiAtomic.no_such_method` prints:

```text
Error: undefined method 'no_such_method' for IyiAtomic.class
```

The follow-up diagnostic also recommends `iyi doc IyiAtomic`.
Scratch source: /tmp/ri-extension-review.TLFCeh/name.ri.
This is evidence of exposure, not proof that all internal names leak.

Checked, overflow probe with `import std/debug`, then:

```text
x = 2147483647
puts x + 1
```

Scratch source: /tmp/ri-extension-stack.QHR8NI/overflow.ri.
Invoked ./bin/ris run with IYI_CACHE_DIR under that scratch directory.
Output:

```text
iyi: panic: arithmetic overflow
0   __iyi_raise_overflow
1   __iyi_main
2   main
```

The actual output includes source sites: src/iyi/prelude.iyi:2086:3,
the scratch file at 3:8, and src/iyi/prelude.iyi:3046:3.
The initial run with the default cache failed on a read-only cache path;
the retry confined cache writes to /tmp and produced the trace above.
Other platforms, optimization modes and debugger presentations:
not checked. This probe establishes the Linux checkout behavior only.

Recommendation: retain upstream implementation identifiers where useful,
but explicitly define their public presentation or a narrowly enumerated
exception. The proposed claim that only compiler readers meet them is
false. This is an execution risk under section 1's fixed decision 4.

### Installed layout is user-visible and includes runtime resources

Checked against Makefile:390-410: install_iyi installs the executable
and daemon, copies the prelude into DATADIR/iyi/src/iyi, copies std
into DATADIR/iyi/src/std, and installs licenses under licenses/iyi.
Makefile:416-422 makes RIS_HOME default to PREFIX/lib/ris, invokes that
installer inside RIS_HOME, then links BINDIR/ris to RIS_HOME/bin/iyi.
Thus the inner share/iyi is under the private lib/ris tree for this
installation path; it is not necessarily PREFIX/share/iyi.

Checked against Makefile:473-479: the base tarball additionally installs
README, SPEC and iyi samples under share/iyi. Makefile:500-509 copies
that package, adds bin/ris as a link to iyi and adds ris documents and
samples under share/ris. Makefile:559,572 embeds share/iyi search paths.
Makefile:113 embeds a lib/iyi search path; that line alone does not
establish that installation populates that directory with files.

Recommendation: adopt section 6's proposed share/ris and lib/ris names,
and state their paths relative to the executable and private install
root. Include daemon, licenses, package assembly and uninstall behavior.
Actual staged installation, relocation and uninstall: not checked.

### Concrete external package changes

Checked by bounded external source reads under
/home/priit/contribute/rispacks, outside fff's repository index:

| Package | Files needing environment spelling migration |
| --- | --- |
| htmlparse | check.sh:7 |
| sha2 | check.sh:6 |
| slim | check.sh:8; slim/spec.ri:76,82 |
| web | check.sh:8; bench/run.sh:9; AGENTS.md:11 |
| htmlparse | bench/run.py:108-112 |
| ricord | bin/test:13,26 |
| sqlite | README.md:225 |

The check and web benchmark shell lines set IYI_PATH and query
`ris env IYI_PATH`; htmlparse's Python benchmark does the same.
Change both export and query to RIS_PATH; slim's nested shell command
needs the same change. The check scripts already use RIS as their
compiler override; no IYI-to-RIS override migration is needed there.
ricord/bin/test sets IYI_CACHE_DIR and IYI_LIBRARY_PATH; convert both.
sqlite's README documents the latter variable for Turso proofs.
slim/bench/run.py:39,41,53-57 shares an environment across ris, iyi and
optional Crystal modes. Split cache settings by compiler, preserving
intentional .iyi and iyi.mod inputs for the iyi modes.

Checked: pg/pg/record_proofs.ri:1 contains a pg/record.iyi comment;
ricord/doc/DESIGN.md:2738 cites src/iyi/region.iyi. Review these path
references according to whether they describe current or historical code.
web/CHANGELOG.md:192 is historical iyi.mod prose, not an executable
manifest requiring conversion.

A bounded filename inventory excluding lib/ and mods/ found ris.mod
files in blog-demo, db, htmlparse, pg, ricord, sha2, slim, sqlite and web,
plus nested projects, and no .iyi sources or iyi.mod/iyi.sum there.
This is a local working-tree inventory, not an audit of published tags,
ignored vendored trees, package caches or every external consumer.
Published compatible versions, ownership and pinned versions: not checked.

Checked: samples/ris/respond.ri and the local ris-bench/ris/respond.ri
are byte-identical (cmp exit 0). goose-evals.sh:18-20 already uses RIS;
its line 47 invokes ris port builds. The inspected ris source directory
and entry scripts had no legacy ris source/environment spellings needing
conversion. Full benchmark overlay and execution: not checked.
ris-bench/run.sh:41 invokes the separate iyi benchmark with an .iyi
input. Preserve that upstream-language row; it is not a ris source.

## Findings

### B1 - Blocker: the kept-name boundary contradicts public behavior

Scope: draft 85-95,112-114,175-177.
The retained-set rationale says only compiler readers meet these names.
The checked section 6 probes disprove that premise for ordinary docs,
diagnostics and stack traces. A fixed decision to rename user-facing
names cannot be implemented without classifying those public exposures.

Checked: src/iyi/io.iyi:437 aliases IO to IyiIO;
src/compiler/iyi/command/doc.cr:292-298,311 prints the target name;
src/iyi/concurrency.iyi:4182 returns IyiTask(T) from spawn;
its lines 3262-3265 embed IyiWorkers.count in failure messages.
src/iyi/prelude.iyi:2382 prints the iyi panic prefix.
The parent probes above confirm actual docs, errors and Linux traces.

Action: enumerate these surfaces and specify public spelling/rendering
while retaining upstream implementation identifiers where possible.
If an exposure must remain, name it as an explicit exception to seek in
the next draft, not as an invisible internal. Add surface regression
cases. Do not reopen section 1's migration decision or rename all compiler
internals merely because one public surface needs a defined presentation.

### M1 - Major: artifact suffixes and public options are unclassified

Scope: draft 66-95,150-154,175-177.
The renamed and kept lists omit .iyimod, --emit-iyimod and --use-iyimod.
Source refusal does not determine artifact compatibility or cache policy.

Checked: src/compiler/iyi/command.cr:60,834,866 exposes these names;
src/compiler/iyi/command/mod.cr:54-64 documents them;
src/compiler/iyi/compiler.cr:704 writes .iyimod paths;
src/compiler/iyi/command/doc.cr:432 discovers that suffix.

Action: classify each public artifact name, define old-artifact reading,
cache handling and diagnostics, and add flag/artifact acceptance cases.
This is separate from the fixed refusal to read old source files.

### M2 - Major: environment migration has no complete behavior table

Scope: draft 75-80,88-89,148-157.
The proposed stderr warning conflicts with the gate's word refused.
The explicit replacement list is absent: examples and IYI_DAEMON_* do
not determine the names to rewrite. Precedence, empty values, multiple
old variables, Crystal fallback and ris env output remain unspecified.

Checked: src/compiler/iyi/config.cr:11-18 selects IYI then CRYSTAL;
src/compiler/iyi/command/env.cr:23-36 separately chooses output names;
src/compiler/iyi/command.cr:1344-1372 separately consumes option input.
LLVM.md:45-48 also documents developer environment controls.

Action: add a complete runtime and compiler-override mapping, separate
retained build constants, and define behavior for old-only, new-only,
both-set, empty and multiple-old settings under ris and Crystal.
Specify exit status, diagnostic frequency and the encountered variable's
name; label the IYI_PATH text as an example if that is its purpose.
Test the table at the lookup and command boundaries.

### M3 - Major: literal rewriting misses semantic and encoded anchors

Scope: draft 69,124-125,140-154.
The script plus literal residual scan cannot establish preservation of
all behavior. Some identity checks join a standalone iyi directory
component; an encoded extension glob contains no literal iyi at all.

Checked: src/compiler/iyi/util.cr:139-143 identifies library sources;
src/compiler/iyi/semantic/semantic_visitor.cr:518-532 identifies std
and host-library sources using a separately joined prelude path;
src/compiler/iyi/compiler.cr:2827-2830 derives tape mode from prelude;
src/compiler/iyi/command/doc.cr:249-257 classifies runtime paths.
src/compiler/iyi/command/check.cr:150-156 scans consumers with
`**/*.[iI][yY][iI]`, missed by both proposed literal operations.

Action: inventory identity predicates, encoded suffixes, casing, slicing
and length-dependent logic. Name explicit manual changes and regression
checks for tape activation, library safety classification, host imports,
docs and affected-consumer discovery. Reuse existing predicates rather
than creating a second parallel identity framework.

### M4 - Major: any-verb refusal lacks a boundary and exclusion matrix

Scope: draft 97-104,152-159.
A single argument fixture cannot prove every verb and discovery path.
Changing a suffix predicate can silently drop a file from a walk instead
of diagnosing it. Mixed source and manifest states also need precedence.

Checked: src/compiler/iyi/command/project_walk.cr:14-33 handles test/spec
discovery with exclusions; command/check_suite.cr:442-469 has its own
walk and format handling. command/doc.cr:131-144 has separate resolution;
mod/installer.cr:25-34 and command/spec_clauses.cr:133-142 discover
manifests. iyi_path.cr:175-186 tries .ri before .iyi today.
These abbreviated source paths are under src/compiler/iyi/.

Action: enumerate direct files by verb, directory scans, extensionless
imports finding old source, both suffixes, mixed manifests and miscased
suffixes. Preserve each command's deliberate exclusions; diagnose an
excluded source if later imported. Specify exit and diagnostic precedence
and integrate one refusal policy into the existing boundaries.

### M5 - Major: installed layout and daemon behavior are incomplete

Scope: draft 81-83,153-164,178-179.
The checked section 6 layout contains nested installation roots, resource
copies, binary links and embedded paths. Checkout success does not prove
installed relocation, daemon discovery, upgrade cleanup or uninstall.

Checked: Makefile:113,390-422,473-479,500-509,559,572;
src/compiler/iyi/command/daemon.cr:119,123-128 maps ris to iyi-daemon
and searches beside the executable and in .build.
Actual installed behavior and upgrade cleanup: not checked.

Action: write complete old/new path pairs including prelude src subtree,
stdlib, executable, daemon, licenses and dynamic-library search paths.
Define installer, tarball, launcher and uninstaller changes together.
Require staged clean install, relocated package, daemon and uninstall
checks without checkout path overrides. Preserve independently installed
upstream iyi; make cleanup ownership explicit.

### M6 - Major: external rollout lacks a bounded, usable migration set

Scope: draft 73-74,152-159,180-181.
Local source renames do not migrate published versions, pinned consumers,
generated child commands or cached dependency trees. Blanket external
rewrites would also change intentional upstream iyi benchmark inputs.

Checked: src/compiler/iyi/mod/fetcher.cr:28-30,62-81 uses versioned
checkouts; mod/sum.cr:31-60 selects a sum and verifies checkout hashes.
The section 6 external file inventory above identifies concrete active
ris consumers, generated commands and mixed-language driver exceptions.
Published compatible versions, package dev worktrees and pins:
not checked; no inference of compatibility is made from local filenames.

Action: name companion dev worktrees, owners, affected files, commands,
delivery order and compatible versions or local replacements before the
compiler stops accepting old settings. Exercise an old fetched package
offline and require an actionable failure without cache rewriting.
Preserve intentional iyi benchmark variants and historical results.
Synchronize respond copies only if their content changes; they match now.

### M7 - Major: commit phases do not establish stable checkpoints

Scope: draft 140-154,165-167.
Mechanical rewriting changes sources, literals and SPEC before manual
compiler/build work and final specification acknowledgements. The stated
three commits have no dependency-complete build/test checkpoints.

Checked: Makefile:332-335,556-560 builds iyi then links ris;
src/compiler/iyi/command.cr:989-990 selects the old prelude;
iyi_path.cr:183-186 resolves extensions independently;
SPEC.md:271-294 defines versions, review locks and changelog checks.
The draft's rewrite scope includes SPEC while its last commit claims
the SPEC and CHANGELOG work.

Action: define stable, buildable phases with their complete dependencies,
or make the coordinated source/compiler/build/proof migration one atomic
landing unit. Keep SPEC and its dated CHANGELOG entry in the same commit.
Name the final integration tree and lock/proof review checkpoints.
No commits are authorized or made by this review.

### M8 - Major: the acceptance baseline cannot be reproduced

Scope: draft 160-164.
The earlier 37 passing scripts are unnamed until a future commit body.
Bootstrap and spec_* shorthand is not an executable acceptance list;
the final green criteria also omit the authoritative complete ris check.

Checked: draft text; src/compiler/iyi/command.cr:57 describes the full
check phases; test/ris/check.sh:27-33 supports configurable compiler
and parallel dispatch. Historical 37-script passing result: not checked.

Action: save the exact bootstrap command, script paths, environment,
expected baseline outcomes and checkpoint commands before implementing.
Require final ./bin/ris check on the completed integration tree, alongside
focused refusal, semantic, installed and external compatibility checks.
That is an implementation acceptance requirement; the present review
does not run the full suite under the user's explicit restriction.

### M9 - Major: worktree preservation is left to the implementer

Scope: draft 137-138,168-171.
Rebased or reset does not specify how retained work survives. The plan
names partial patches but not their saved location, replay ownership,
integration method or verification after the rename.

Checked: draft wording, an implementation-plan gap.
Actual uncommitted worktree contents, minitest and user profile:
not checked. No reset, rebase or launcher/profile edit was performed.

Action: inventory every worktree at implementation time, save retained
changes, identify replay owners and select a preservation-safe integration
step per branch. Do not treat reset as interchangeable with rebase.
List user-owned launcher/profile updates without silently modifying them.

### N1 - Minor: checksum migration lacks an explicit outcome

Scope: draft 73-74,147,155-157.
The old sum is no longer read, but the gate and migration instruction
cover only the manifest. A new ris.mod beside an old iyi.sum is undefined.

Checked: src/compiler/iyi/mod/sum.cr:25-43 selects the sum from manifest
name and loads known hashes; lines 46-58 compare or add expected hashes.
The proposed post-migration mixed-state outcome has not been implemented
or probed. Ignoring an old sum could lose previously pinned verification.

Action: specify ignore versus refusal, the migration diagnostic and how
to preserve existing hashes; add mixed manifest/sum cases. Address this
as concrete integrity risk coverage rather than generic security prose.

### N2 - Minor: the merge-conflict prediction is too absolute

Scope: draft 112-114.
Checked: draft says every later merge conflicts; AGENTS.md:92-97 and
CONTRIBUTING.md:20-22 justify retaining names, not that universal claim.
Action: say renamed identifiers increase conflicts when upstream touches
them. Downgraded from F7-1's Major: this wording does not itself block
implementation once the concrete public naming contract is resolved.

### N3 - Minor: one reader experience is generalized to all readers

Scope: draft 7-10.
Checked: draft wording. Reader experience and aggregate counts:
not independently checked by this review.
Action: state the observable mixed-extension problem and retain the
reported user experience as motivation without a universal reader claim.

## Reviewer completion and reading evidence

| Stage | Fresh reviewer | Standard | Status |
| --- | --- | --- | --- |
| 5 | egm-zoom-out | zoom-out | completed |
| 6 | egm-comprehension | none | completed |
| 7 | egm-design | feature-spec | completed |
| 7 | egm-structural | feature-spec | completed |
| 7 | egm-style | none | completed |
| 8 | egm-zoom-out | zoom-out | completed |
| 9 | egm-implementation-readiness | readiness | completed |
| 9 | egm-codebase-details | readiness | completed |
| 9 | egm-style | none | completed |

Each reviewer returned an actual completed result and read manifest.
All reported complete persona and target reads and complete assigned
standards. No requested reviewer failed or was counted as a clean result
without a report. Personas and standards resolved under the EGM root,
not similarly named project files. Readiness abbreviates the bundled
implementation-readiness-standard.md; other standards similarly resolve
under resources/document_standards/.

Referenced documents were read in relevant parts: AGENTS.md, SPEC.md,
README.md, LEARN.md, CONTRIBUTING.md, UPSTREAM.md, TODO.md, LLVM.md,
CHANGELOG.md, std-spec/DRAFT.md, src/std/SPEC.md, Makefile and
test/ris/check.sh. Reviewers also read the draft's named compiler paths,
prelude/hello sources and additional evidence cited in their findings.
Stage 7 document-reference addenda completed initially partial reading
lists; they did not change those reviewers' findings.
Stage 8 read all three earlier stage reports, as specifically selected.
The codebase reviewer additionally inspected the external drivers named
above. The parent re-read critical source excerpts and checked the
reported external driver lines, then ran the four small public-surface
probes: invalid method, doc IyiAtomic, doc IO, and overflow with debug.

No exact aggregate inventory, historical exercise success, all published
packages, every worktree's contents or non-Linux runtime was established.
Unverified draft assertions remain not checked, not assumed true.
No full suite was requested for this report-only task; none was run.

## Comprehension result, preserved

### What this proposes

The draft proposes one migration from .iyi to .ri for ris sources,
including the prelude, samples, compiler inputs and supporting scripts.
It also proposes replacing user-facing iyi names with ris names while
retaining compiler internals needed for upstream merges. Old source and
manifest names would produce migration instructions instead of being
accepted.

### How the existing system works, per this document

The draft describes a mixed naming system: both source extensions work,
the prelude lives under src/iyi, and old manifest and environment names
remain accepted. It says compiler internals retain upstream Iyi names
under an existing repository rule. Its file counts and worktree inventory
are draft assertions; those inventories were not independently checked
during this comprehension review.

## Traceability matrix

Every raw finding maps below; Minor is the report's name for EGM Nit.
Overlaps were deduplicated into action items, not counted by reviewer.
S7-1's general risk-coverage concern maps to concrete risks and mitigations
instead of demanding unrelated security or scalability boilerplate.
No finding reopens section 1. Findings are recorded for draft revision;
this is one report-only pass, not a claim of remediation convergence.

| Raw finding | Final item | Disposition |
| --- | --- | --- |
| Z5-1 | M4 | discovery integrations |
| Z5-2 | M7, M8 | stable landing and final check |
| Z5-3 | M6, N1 | dependencies and checksum integrity |
| Z5-4 | M5 | installed acceptance |
| Z5-5 | M2 | environment contract |
| C6-1 | M2 | warning versus failure |
| C6-2 | N1 | mixed checksum state |
| D7-1 | M1 | artifact contract |
| D7-2 | M2 | runtime and Crystal compatibility |
| D7-3 | M3 | semantic identity predicates |
| D7-4 | M5 | complete installed layout |
| D7-5 | M4 | exclusions and precedence |
| S7-1 | M2, M3, M5, M6, N1 | concrete risk coverage |
| F7-1 | N2 | downgraded wording-only Major |
| F7-2 | M2 | diagnostic names actual variable |
| F7-3 | N3 | reader generalization |
| Z8-1 | M4 | earlier concern unresolved |
| Z8-2 | M3 | earlier concern unresolved |
| Z8-3 | M7, M8 | earlier concern unresolved |
| Z8-4 | M5, M6 | installed and external boundary |
| Z8-5 | M1, M2, N1 | public compatibility table |
| Z8-6 | N2 | unsupported merge absolute |
| R9-1 | M7 | stable commit dependencies |
| R9-2 | M2 | explicit mapping and behavior |
| R9-3 | M4 | executable refusal matrix |
| R9-4 | M3 | encoded suffix scan |
| R9-5 | M5 | install, daemon and cleanup |
| R9-6 | M8 | reproducible acceptance |
| R9-7 | M6, M9 | ecosystem and work preservation |
| B9-1 | B1 | public Iyi naming contradiction |
| B9-2 | M5 | nested install and daemon map |
| B9-3 | M6 | active external consumers |
| B9-4 | M6 | upstream benchmark exemptions |
| B9-5 | M1 | artifact names and compatibility |
| B9-6 | M4, M7, M8 | discovery, phases and gates |
| T9-1 | M8 | exact baseline commands |
| T9-2 | M9 | preservation, merged with R9-7 |
| T9-3 | M5 | complete installed path pairs |
| T9-4 | M6 | named companion updates |

## Report verification

Only this consolidated report is retained with DRAFT.md; stage reports
were removed after consolidation. DRAFT.md, SPEC.md, src/ and test/
were not changed. No commits were made. Report lines were checked to
be at most 80 characters. Compiler probe sources and cache stayed in
/tmp. Runtime probes are evidence for this checkout, not full tests.
