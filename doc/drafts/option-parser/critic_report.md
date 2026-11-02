# Goldfish Review Report: Stage 7, Critic Review

**Target:** `doc/drafts/option-parser/option-parser.md` (third draft,
FeatureRange 1-210)

## Reviewer Status

| Reviewer | Status |
| --- | --- |
| `design_critic` | completed |
| `structural` | completed |
| `style` | completed |

No Blockers. Majors: design 5, structural 2, style 5. Nits merged.

## Major findings

### D1. The probes do not cover the proposed shape - design
Lines 22-26, 74-80, 112-114, 143-147. p5 appends to a caller's Array;
the design stores into an owner's fields via a parameter. The refusal
of a shorter-lived `args`, and a clear while views are live (SPEC 3.3),
are unprobed. The refusal of `args` lands on a std line.

### D2. The stub is not proven to win over the capture refusal - design
Lines 85-86, 154-166. p9's block captures nothing, its raise is
guarded, and its def is in the same file.

### D3. Missing alternative: a handle returned by `on` - design
Lines 137-141, 168-191. `e = parser.on(…)`, `found[e]?`: a misspelling
is an undefined local at compile time; the name is written once. The
run-time panic only fires when the lookup runs.

### D4. RisOptions is unspecified in the error cases - design
Lines 116-135. A value flag last after the opt-in; a value given to a
switch; a bundle key built on `parse`'s scratch; a lookup before parse.

### D5. Keeping `OptionParser` conflicts with AGENTS.md naming - design
Lines 183-188, 205-206. Its contract changes; `invalid_option` /
`missing_option` keep names with a new meaning. State the exception or
rename.

### S1. Risks name no mitigation for a stub never called, nor for
reusing `found` - structural (lines 199-209, 113-114).

### S2. Probe evidence is listed only for passing probes - structural
Lines 39-42, 49-86. List the refused ones too, or one table.

### Y1-Y5. Style - style
"as today" contradicts Problem (120-121); the stub message chains
statements with commas (158-160); "registrations included" is ambiguous
(112-114); two over-long sentences (22-26, 170-177).

## Nits (merged)

* Citation forms: bare "(3.2)"; path styles mixed.
* compiler.cr:2834 is :2833; option_parser.iyi:117 is the command
  branch (the dashed stores are :121, :134).
* check.sh "never builds it": std_text_plain.ri imports it.
* `banner`, `separator` unmentioned; help could write into the caller's
  `String::Builder`; the third panic text missing; `invalid` / `missing`
  alias growing fields; sizing up front (AGENTS.md); no Goals line.
* Wording: lines 5-7, 38-42, 64, 69, 99, 105-108, 116, 141, 162-165,
  165 and 187-188 (claims about the agent), 207-209.

## Resolution (author)

New probes on minitest, in `probes/`:

* p10, p12: a `{% raise %}` in a def with no block fires even when the
  def is never called (`parse(args)` stub); p11: the flag guard does not
  change it. Only block-taking defs can be stubs.
* p13c: a block-taking stub in an imported module, called with
  `{ |v| ext = v }`, reports its message at the caller's line and no
  capture refusal (D2).
* p13a: an owner storing through its own `add(index, value)` is
  refused, "cannot store request tape data on the program tape". p14a:
  `parse` appending to the owner's field directly builds and runs (D1).
* p14b: two parses on one `found`, keeping a value from the first,
  builds and reads right: the value views `args`, not `found`.
* p14d: `args` built in a loop round is refused, at the append inside
  the library, not at the caller (D1): recorded under Risks.
* p15a/b: the same with a plain caller Array and a handle.

Draft changes: D3 adopted (`on` answers a `RisFlag`; lookups take it;
no string lookups, no registration copy). D4: a table of cases; the
found entry is the registration index, never a built key. D5: stated
as an exception for the owner to confirm; the opt-in is renamed
`record_errors`. S1, S2, style and nits applied.
