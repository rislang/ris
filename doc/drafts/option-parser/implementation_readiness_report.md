# Goldfish Review Report: Stage 9, Implementation Readiness

**Target:** `doc/drafts/option-parser/option-parser.md`, Implementation
Plan (fifth draft, lines 250-274)

## Reviewer Status

| Reviewer | Status |
| --- | --- |
| `implementation_readiness` | completed (verdict: not ready) |
| `codebase_details` | completed |
| `style` | completed |

One Blocker, about 15 Majors after merging, Nits.

## Blocker

### `puts parser` does not call `to_s : String` - codebase_details
Crystal's `IO#puts` calls `to_s(io)` (`src/io.cr:178-181`), so the help
idiom would print `#<OptionParser:0x…>`.

**Contested, with a probe.** ris's prelude is `src/iyi/`, not
`src/io.cr`: `puts(value)` writes `value.to_s`
(`src/iyi/io.iyi:365`). p18 prints both `to_s : String` and
`to_s(io : String::Builder)`. An `IO` parameter is refused in ris ("a
text parameter takes `String::Builder`"). The draft now cites p18.

## Major findings (merged)

* The naming decision has no step (readiness 1).
* The `protected` accessor is unproven, no fallback (readiness 2,
  codebase 9).
* "Sizes `found` from `args.size`" has no API; no Array reserve exists
  (readiness 3, codebase 2).
* Field layout and public signatures not given; help format, the
  pair-mismatch and `-` messages unstated (readiness 4, codebase 3, 13).
* Test path `test/ris/src/std/` does not exist; no check.sh block, pass
  line or stats needles; refused tests cannot check the line with
  `expect`; only the `on` stub is tested (readiness 5, codebase 6, 14,
  style).
* Panics cannot be checked inside one run (readiness 6, codebase 4).
* Steps 1-3 leave the tree unbuildable; no final gate; `run.sh` never
  reads `-e` (readiness 7, codebase 7, 8, style).
* The doc comment the Risks rely on is in no step (readiness 8).
* Ported cases omit bench cases; the bench's mutation proofs and release
  build go silently (codebase 5, readiness nit 5, 7).
* `RIS_TAPE_STATS=1` has no pass condition (style).

## Nits (merged)

Stub texts not exact; TODO.md lists OptionParser twice; LEARN.md and
UPSTREAM.md sections unnamed; goose-evals.sh has no flag-parsing eval;
`dependency_floor.sh` names the Crystal-side file (no edit); a
`RisFlag` from another parser reads by index; wording ("pairs", "port
… 's cases", "fixed args").

## Resolution (author)

* p17a / p17b: `protected def given` is reached from `OptionParser`
  and refused to a program ("protected method 'values' called");
  `ris doc` skips protected defs (`command/doc.cr:325`).
* Sizing dropped: fields are made once and refilled with `clear`; each
  reserves its own space (TAPE_API.md); the gate checks 0 moves.
* The plan is rewritten in two phases, each one commit with a gate:
  phase 1 the library, `test/ris/option_parser.ri` (`want=` block,
  stats needles), a panic program run per case, four refused files
  checked by message and `file:line`, the bench removed (accepted, with
  reason); phase 2 `ls.ri` with `args_ls="-l -e .txt data"`, the
  blocked repro, both TODO.md entries, LEARN.md section 2, UPSTREAM.md
  "Stays in ris". Fields, signatures, help format and every message are
  given; the header comment rewrite lists what it states.
* Naming: the plan implements `OptionParser`; a `RisOptionParser`
  answer from the owner is applied before phase 1.
* goose-evals.sh: no eval covers it; the four port lines are recorded.
