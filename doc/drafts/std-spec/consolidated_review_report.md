# EGM consolidated review: std specification

Target: doc/drafts/std-spec/DRAFT.md, lines 1–190.
Date: 2026-11-13. Reviewer account: hobune.
Result: changes required before implementation.
Findings: **0 Blocker, 7 Major, 4 Minor**.
EGM's Nit severity is reported here as Minor.

## Execution and defaults

Followed docs/codex.md and skills/egm-review/SKILL.md from:
`/home/priit/.claude/plugins/marketplaces/egm`.
All personas and standards were resolved against that plugin root.

The user selected consolidated full flow, without stage checkpoints.
Default choices: no additional historical context; use referenced files
and required source verification; use one instance of each rubric;
proceed through all stages without remediation. Only reports authorized.

The nonstandard `## 5. Migration` heading was the default semantic split:
FeatureRange 1–157; DetailedRange 158–190. Section 6 was binding context
for every reviewer. No settled decision was reopened. Recommendations
below concern carrying those decisions out.

Stages ran in order 5, 6, 7, 8, 9. Direct dispatch was used; reviewers
within stages 7 and 9 ran concurrently. Each reviewer was a new native
subagent with `fork_turns: "none"`, no parent transcript or memory lookup.
Each returned a completed result and read manifest. The host exposes
completion messages, not individual child tool transcripts; this limits
independent auditing of their read manifests. The parent independently
read the source evidence retained in the consolidated findings.

Fresh conversation context shares the filesystem. One readiness reviewer
reported incidental FFF report snippets, while stating they were not used
as evidence. Only Stage 8 was deliberately supplied earlier reports.

| Stage | Persona | Standard | Status |
| --- | --- | --- | --- |
| 5 | egm-zoom-out | zoom-out | completed |
| 6 | egm-comprehension | none | completed |
| 7 | egm-design | feature-spec | completed |
| 7 | egm-structural | feature-spec | completed |
| 7 | egm-style | none | completed |
| 8 | egm-zoom-out | zoom-out | completed |
| 9 | egm-implementation-readiness | implementation-readiness | completed |
| 9 | egm-codebase-details | implementation-readiness | completed |
| 9 | egm-style | none | completed |

Standard filenames end in `-standard.md` under
`resources/document_standards/`. Persona files are `zoom_out.md`,
`comprehension.md`, `design_critic.md`, `structural.md`, `style.md`,
`implementation_readiness.md` and `codebase_details.md` under `agents/`.
Every assigned persona, standard and the full target were reported read.

## Comprehension result

### What this proposes

Move each standard library promise into a comment immediately above its
own executable proof block. Add module-qualified identifiers to the
existing clause, review and lock workflow. Section 6 makes the mechanism
available to any root's `src/`, while limiting this migration to std.

### How the existing system works, per this document

The draft describes a root specification whose clauses are connected to
proof blocks or older test tags. Clause text determines a version hash,
and `.spec.lock` records reviewed versions. These mechanics are checked
in `src/compiler/iyi/command/spec_clauses.cr:159,243,305,364,702` and
`SPEC.md:259`. The draft says the separate std specification is outside
that workflow; root spec-file selection is checked at
`src/compiler/iyi/command/spec_clauses.cr:144–157`.

## Major findings

### M1. Define general discovery and module identity

Scope: draft 67–69,109–115,148–149,189–190.
Lenses: architecture, comprehension, design, structure and style.

Sections 3–4 restrict discovery and ownership to src/std and postpone
general src support. Decision 6.4 requires the general mechanism now;
only the migration is std-specific. The implementer still must choose
the path base, nested identifier grammar, source extensions and handling
of colliding identities. Orphan/mismatch validation also needs explicit
comment boundaries and ownership rules, not just the two error names.

Action: align sections 3–4 with 6.4. Specify identities and corrective
paths for ordinary, nested and std modules; state the traversal boundary
and exclusions. Cover a non-std src module, both intended extensions,
nested paths, duplicate owners, malformed/orphan comments and excluded
trees in the acceptance fixtures. Keep std as the initial migration.

Checked: `src/compiler/iyi/command/project_walk.cr:14–27` supplies the
existing traversal and excludes symlinks, lib/, mods/, dot directories
and marked fixture trees. Proof discovery already uses that walk for
both source extensions at `spec_clauses.cr:305–310`. The current parser
grammar is at `src/compiler/iyi/syntax/parser.cr:270`.
Here and below, unqualified spec_clauses.cr means
`src/compiler/iyi/command/spec_clauses.cr`.

### M2. Separate live duplicate checks from historical number reuse

Scope: draft 70,113,152–154.
Lenses: architecture, comprehension, design, structure and style.

“Gaps-reused are refused as for N.M” is both undefined and a mistaken
equivalence. A live duplicate check cannot distinguish a never-used
number from a previously removed one. The unchanged lock design does
not supply that history. An implementer could silently omit the promised
refusal or add unplanned persistent state.

Action: define reuse precisely and distinguish current validation from
the permanent identity policy. Specify the intended enforcement or
review obligation; do not imply historical enforcement already exists.
If automatic refusal is required, document its retained evidence and
test remove, acknowledge, then reuse. Positive-number validation is a
separate requirement from retirement history.

Checked: spec_clauses.cr:206–209 rejects duplicate live ids;
:237–240 checks numeric shape without positivity/history checks;
:380–388 prunes vanished ids from the lock.
The permanent-number policy appears in src/std/SPEC.md:6–7.

### M3. Define the text baseline for unchanged migration hashes

Scope: draft 83–102,163–171.
Lenses: comprehension, intermediate architecture and codebase details.

Old clause text includes parenthesized exercise paths; the proposed
comments omit them. Whitespace reflow preserves normalized text, but
removing those paths changes it. The identical-version gate therefore
lacks a consistent old/new extraction contract.

Action: state whether proof citations remain verbatim in normative
comments. Otherwise define the baseline transformation and resulting
version policy explicitly. Compare the module subset, excluding root
clauses, using the same extraction rules on both sides.

Checked: src/std/SPEC.md:1749–1752 includes json.1's exercise citation;
draft 85–89 omits it. spec_clauses.cr:169–172 hashes all normalized
clause text; :243–244 computes its SHA-256 prefix.

### M4. Preserve and expose every todo reason

Scope: draft 78–79,109–124,165–171.
Lenses: architecture, comprehension, readiness, codebase and style.

The gate promises identical todo reasons, but its baseline only records
ids and versions. Marker reasons and block todo flags have different
representations today. The source also contains multiple reasons for
one clause, which singular reason transfer does not address.

Action: capture ids, normalized text/versions and all reasons in the
baseline. Define lossless normalization into the owning block, escaped
string handling, scanner storage and JSON reason output. Include log.9
and an exact reason round-trip fixture. Specify whether block reasons
also appear in `ris spec todo`, so moving them does not hide that work.
This preserves the decided adjacent comment and todo-block forms.

Checked: src/std/SPEC.md:1895–1900 gives log.9 three markers.
spec_clauses.cr:49–50 stores block todo as Bool; :326–327 discards
reason text when scanning blocks; :573–575 exports marker reasons;
:620–624 exports a block Bool. Its todo listing at :896–918 covers
markers/test reasons, not block reasons. Marker text is separate from
the clause hash at :170–185. Existing reason scanning is at :464–471.

### M5. Preserve external exercise coverage before removing producers

Scope: draft 163–176,180–185.
Lenses: architecture, readiness, codebase and structure.

Moving in-language checks and preserving their count does not preserve
the shell consumers of an exercise program. Those consumers can provide
independent differential, refusal and release-mode coverage. Removing
the producer or its runner entry without an explicit replacement can
break or silently discard those checks.

Action: inventory each module's program checks, shell assertions,
fixtures, output consumers and build modes. Map them to destination
blocks and remaining harness invocations before deleting dependencies.
Preserve the settled requirement that every existing exercise proof
moves; no tag or todo substitution for tested clauses is proposed.

Checked: test/cli/std_json_exercise.sh:59 builds that exact exercise;
:78–99 checks output/sentinels/corpus; :97–120 validates JSON with
Python; :126–129 runs release mode; :134–179 runs negative programs.
src/compiler/iyi/syntax/parser.cr:311–343 constrains the spec section.
test/cli/spec_blocks_program.sh:69–85 demonstrates reusable program
proof facilities, without proving replacement differential coverage.
The wider per-module consumer inventory is not checked in this review.

### M6. Give each module a stable migration checkpoint

Scope: draft 160–176 and section 4 dependencies.
Lenses: readiness, codebase and style.

The plan requires one green module commit at a time, but describes the
967-clause comparison before acknowledgements as an aggregate step.
The first partial migration needs its own preservation and review gate.
The written sequence also puts a green check before exercise deletion.

Action: define this order per module: capture baseline, migrate proofs
and consumers, compare that module, review/ack, remove emptied producers,
run checks, then commit. Retain the final aggregate comparison. State
when root SPEC/AGENTS changes and the short std document land, and what
must be green in each phase. These are future implementation steps;
this review performs no commits or suite runs.

Checked: spec_clauses.cr:533–540 marks unlocked blocks 'to review';
:851–860 makes that state fail the spec check. An acknowledgement is
therefore needed before the proposed green intermediate checkpoint.

### M7. Define the nondecreasing check-count measure

Scope: draft 174–185.
Lens: implementation readiness.

“Number of checks” has no counting unit. Assertion calls, Boolean
conditions and executed cases differ, especially through helpers and
loops. Without a reproducible measure, the settled count requirement
cannot establish that the migration preserved its baseline.

Action: define the counting unit and evidence format for helpers,
compound assertions, repeated cases and shell checks. Record a mapping
from each baseline check to its destination proof. Apply the same
measure before and after each module; retain external coverage per M5.

Checked: test/cli/std_json_exercise.iyi:38–45 mixes direct failures and
an assertion helper; :76 has several conditions in one assertion.
These concrete forms require a consistent counting definition.

## Minor findings

### N1. Fix the stale decision reference

Scope: draft 122. Lenses: comprehension, structure, style.
Checked against draft 178–190: 'see question 2' should name decision 6.2.

### N2. State the owning-block exception in label fixing

Scope: draft 79–80,104–105,119–120. Lenses: design and architecture.
Explicitly exempt owners from label generation and verify idempotence;
retain normal labels for referencing blocks.
Checked: spec_clauses.cr:763–786 rewrites missing/nonmatching labels;
:794 invokes the fixer before checking. This is an omitted integration
detail, not a request to alter the settled adjacent-comment decision.

### N3. Clarify the migration-script instruction

Scope: draft 163–167. Lens: style.
Checked against the text: specify one script processing modules or one
script per module; repair the sentence fragment and 'the / block' split.

### N4. Mark the baseline commit as already completed

Scope: draft 7,160. Lens: parent verification.
The file is tracked now; 'untracked' and the prerequisite commit are
stale. Mark that prerequisite complete rather than instructing a repeat.
Checked: `git ls-files --error-unmatch src/std/SPEC.md` exited 0 and
printed the path. `git log -1 --format='%h %s' -- src/std/SPEC.md` gave:
`2739b82d5 std: commit the one-file specification before the move`.

## Traceability matrix

Raw reviewer IDs remain here after stage-report removal. Split entries
are mapped to all relevant actions; repeated findings are counted once.

| Action | Raw findings |
| --- | --- |
| M1 | Z5-1, C6-1, D7-1, T7-1, T7-3 (discovery), S7-3, Z8-1 |
| M2 | Z5-4, C6-3, D7-2, T7-2, S7-1, Z8-4 |
| M3 | C6-2 (text), Z8-3 (text), B9-1 |
| M4 | Z5-3, C6-2 (reasons), Z8-3 (reasons), R9-1, B9-2, S9-1 |
| M5 | Z5-2, T7-3 (proof preservation), Z8-2, R9-2, B9-3 |
| M6 | R9-3, B9-4, S9-3 |
| M7 | R9-4 |
| N1 | C6-4, T7-4, S7-2 |
| N2 | D7-3, Z8-5 |
| N3 | S9-2 |
| N4 | Parent git verification |

T7-3's general risks-and-limits request is consolidated into concrete
discovery/ownership and migration safeguards in M1/M5, rather than
counted as a separate generic documentation finding. S9-3 is raised
from editorial Nit into M6 because the verification order matters.
No draft mitigation closed an earlier risk during Stage 8.

## Evidence coverage and limits

Reviewers read relevant parts of spec_clauses.cr, parser.cr,
project_walk.cr, check_suite.cr, SPEC.md, src/std/SPEC.md, json.iyi,
std_json_exercise.iyi/.sh and the referenced spec CLI gates. Stage 5
also inspected README.md, .spec.lock, CHANGELOG.md and AGENTS.md.
Stage 8 read the three earlier reports as required. Stage 9 readiness
also inspected test/ris/check.sh:1–45. Search used FFF first.

All retained current compiler/ris spec claims above are marked checked
against source. No probe was needed. Broad draft assertions such as
all-tool absence, the aggregate 967/837 counts, full module/tag inventory
and JSON runtime/tape semantics were not independently checked; they
remain draft inputs, not established review conclusions. No inferred
performance or security claim is presented as a measured result.

Only review reports were written. DRAFT.md, SPEC.md, src/ and test/
were unchanged; no commit was made. Stage reports were removed after
synthesis, retaining this consolidated report and the original draft.
The full test suite was not requested and was not run. Report-only
verification checks line length and whitespace, not compiler behavior.
