# EGM Consolidated Review: OptionParser on ris

Target: `doc/drafts/option-parser/option-parser.md`. Five stages, run
in order; after each, the author resolved the findings in the draft
before the next stage. Every compiler claim was checked by a probe on
minitest at 6173b7918 (`probes/`, p1-p18).

| Stage | Blockers | Majors | Outcome |
| --- | --- | --- | --- |
| 5 Zoom Out | 0 | 6 | blocks, annotation, commands dropped |
| 6 Comprehension | 0 | 5 | no iyi mode; stubs unconditional |
| 7 Critic | 0 | 12 | `RisFlag` handles; error-case table |
| 8 Zoom Out | 0 | 1 | identity check dropped |
| 9 Readiness | 1* | ~15 | plan rewritten, two gated phases |

Reports: zoom_out_report.md, comprehension_report.md,
critic_report.md, intermediate_zoom_out_report.md,
implementation_readiness_report.md.

\* Contested by probe p18: ris's `puts` prints `to_s : String`.

## Decisions the review changed

* Values are read after `parse` through `RisFlag` handles into a
  `RisOptions` owner; a misspelled flag is a compile error.
* All block forms go; block-taking defs become `{% raise %}` stubs
  reported at the caller's line (p13c). Defs without a block cannot be
  stubs (p10-p12); `parse(args)` falls to the overload error (p16).
* No SPEC or compiler change. Commands, repeated values and typed
  values are out of scope.

## Decided by the owner (2026-11-02)

* The name stays `OptionParser`, an exception to AGENTS.md's renaming
  rule (draft, Naming).
* Accepted risk: a shorter-lived `args` is refused inside std, not at
  the caller (p14d); TODO.md gets the checker gap.
