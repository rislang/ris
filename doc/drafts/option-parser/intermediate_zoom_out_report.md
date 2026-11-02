# Goldfish Review Report: Stage 8, Intermediate Zoom Out

**Target:** `doc/drafts/option-parser/option-parser.md` (fourth draft,
lines 1-267)

## Reviewer Status

| Reviewer | Status |
| --- | --- |
| `zoom_out` | completed |

Verdict: no Blockers. The changes since Stage 5 removed the block path,
`@[KeepsBlock]`, commands, string lookups, the registration copy and the
`ris_no_gc` condition: one way to read flags, no SPEC or compiler
change.

## Findings

### 1. The cross-parser check is speculative - Major
Lines 133-136, 215-217. The `object_id` and count check guards a
mistake no program or probe shows, and is the only stated reason for
`RisOptions` over a plain Array. Give the real reasons (one argument
carries values and error lists; `found[flag]?` reads) and drop the
check; a read before parse answering nil is safe.

### 2. Direct appends expose `found`'s fields - Nit
Lines 129-131, 152-153. Say how `parse` reaches them and accept it.

### 3. A dashless `on` is a second help-line mechanism - Nit
Lines 117-120. What does it answer? `separator` already adds lines.

### 4. p14d's refusal lands in std - Nit
Lines 231-234. Record the checker gap in TODO.md; declare the gate's
`args` and `found` in one scope.

### 5. The naming exception has no fallback - Nit
Lines 189-196. Say what happens if the owner says no.

### 6. The probe table is long for Problem - Nit (optional)
Lines 50-95.

## Resolution (author)

* 1: the identity check is dropped; `RisOptions`' reasons are stated; a
  read before parse answers nil / false.
* 2: one line: `parse` uses `RisOptions`' fields through a `protected`
  accessor (same file); `ris doc` lists only the readers. Plan step 2
  probes that `protected` keeps p14a's acceptance.
* 3: a dashless name is refused at `on` ("not a flag: deploy; list
  commands with separator, dispatch on rest[0]"); `separator` writes
  the command list.
* 4: plan adds the TODO.md item; the gate declares both in one scope.
* 5: fallback sentence added.
* 6: kept: Stage 9 reviewers check claims against it.
