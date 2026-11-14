# Goldfish Review Report

**Target:** `doc/drafts/checker-open-questions/checker-open-questions.md`
(whole draft)

## Reviewer Status

| Reviewer | Status |
| --- | --- |
| `design` | completed |
| `codebase-details` | completed |
| `implementation-readiness` | completed |
| `zoom-out` | completed |

Severity: 2 Blocker, 8 Major, 7 Minor.

## Blockers

### B1. Q2's self-holder rule is unsound and decided before the facts

* **Lens:** design, codebase-details, zoom-out, implementation-readiness
* **Scope:** Q2
* **Problem:** The rule "a call on `r` that shrinks only `r`'s own fields
  kills no view held by `r`" lets `r` keep a view into its own buffer
  across a refill. That is the dangling view SPEC 3.3 refuses. The draft
  leaves open whether the decoder is a class. The code answers it:
  `ZipEntryReader` is a class (zip.ri:825), and `@decoder` (zip.ri:911) is
  a union of classes (Inflater, Bzip2Reader, ZstdReader, XzReader). The
  buffer lives in another object, which the rule does not cover. The
  draft also omits TODO.md:278-280: the reader is blamed even when the
  read sits in its own def.
* **Fix:** Restate the rule for a field that references another object.
  Allow it only when no view field of `r` roots in the shrunk storage,
  proven by summary. Write it as a SPEC 3.3 amendment with a refused test
  in which `r` holds a self-view across `read`. Otherwise keep Q2 open in
  TODO.

### B2. No tests, gates or order of work

* **Lens:** implementation-readiness, design, zoom-out
* **Scope:** whole draft
* **Problem:** No question names its passing test, its refused test
  (`test/ris/refused/`), the expected diagnostic or the gate. The order
  matters. Q1's checker fix newly refuses the current toml.ri:2713 and
  yaml.ri:2983 (`RisDecoded(T).new(value).value`), so the `read_into`
  port has to land with the fix or before it.
* **Fix:** For each question, give the tests, the diagnostic text, the
  gate (`test/ris/check.sh`, `ris check spec`), the benches it unblocks
  (now 114 of 130) and the step order.

## Major

### M1. Q1 conflicts with SPEC 2.2, and its std half is underspecified

* **Lens:** design, implementation-readiness, zoom-out, codebase-details
* **Scope:** Q1
* **Problem:** `Array(T)` with a derived `T` that has growing fields is a
  runtime-sized collection of growing values, which SPEC 2.2 refuses
  ("use SlicePool"). The draft gives no checker file or function. It does
  not say whether the lists of forms and growing fields are complete.
  It does not settle yaml, the derive macro, the signature, or what
  happens to `RisDecoded`. Under AGENTS, a dropped name is removed.
* **Fix:** Say where an element's field space is rooted under 2.2. Copy
  JSON's derive and `read_into` (json.ri:374, 4010) for both toml and
  yaml. Use the checker's owner notion instead of a list of field types.
  Land the soundness fix as its own first step.

### M2. Q3: the method name is wrong and the storage conflicts with 2.1/2.2

* **Lens:** codebase-details, design, implementation-readiness
* **Scope:** Q3
* **Problem:**
  * `Router#add` does not exist. Routes register through `handle`
    (router.ri:551). The handler call is at router.ri:591, not :594.
  * `Pattern` is a class with Array fields (router.ri:144, 177), so it is
    an owner. Under SPEC 2.1 a def may not return its own local owner, and
    an owner is never an element or field initializer. N slots of
    patterns is the shape 2.2 refuses. "Declare one owner per scope" is
    not SPEC text, and 1.9 is the wrong citation.
* **Fix:** Cite 2.1. Name the real storage (SlicePool, or one owner with
  flat arrays and indices). Give the new `Pattern.new` and the
  `handle`/slot signature, and say whether `Pattern.parse` goes away.

### M3. Q4 proposes `File.each_line`, which already exists

* **Lens:** codebase-details, zoom-out, implementation-readiness
* **Scope:** Q4
* **Problem:** `File.each_line(path, &block)` is at file.ri:1703. The
  three-argument `read_lines` is speculative. It also puts views into an
  unfinished `String::Builder`, and the draft does not say whether 1.6 or
  2.2 allows that.
* **Fix:** Remove `read_lines` (file.ri:1674) and list its callers to
  move to `each_line`. Add the three-argument form only if a caller needs
  every line at once.

### M4. Q5 omits SPEC 1.8 and leaves context sensitivity open

* **Lens:** design, codebase-details, zoom-out, implementation-readiness
* **Scope:** Q5
* **Problem:**
  * Program data initialization is SPEC 1.8, but the draft says "SPEC
    3.x: none" and cites only 5.1.
  * `Zone#initialize` (time.ri:743) is also reached from request code.
    Classifying its stores only "when reached from a constant" needs
    per-context summaries, which the draft does not describe. It also
    does not say how deep "reached" goes or how 1.8's never-suspending
    rule is checked.
  * x509's second cause, `cert(hex)` returning a view of its def's bytes
    (TODO.md:312-313), is left out.
  * There is a cheaper path that needs no checker change: build the
    values in a def or a lazy accessor, which already compiles.
* **Fix:** Cite 1.8. Either specify the context split, or take the
  def/accessor path and defer the checker change.
  `TapeProgramChecker#initializer` is at tape_program_checker.cr:108.

### M5. Q6 does not show why the refusal goes away, and its scope is narrow

* **Lens:** design, zoom-out, implementation-readiness, codebase-details
* **Scope:** Q6
* **Problem:** `to_a(into:)` still appends inside the same opaque `each`
  block, so the checker sees nothing new. The proc calls are in the
  adapters (iterator.ri:549, 565), not in `to_a` (iterator.ri:225).
  `Enumerable#to_a` (enumerable.ri:56) has the same shape and is not
  discussed. Neither are the `to_a` methods in indexable, set and slice.
* **Fix:** Show the checked path, or drop `Iterator#to_a` in favour of
  `each { |e| arr << e }`. Say what happens to the other `to_a` methods.
  Note that samples/ris/std_iterator.ri does not build (TODO.md:36-38).

## Minor

* **N1 (header):** cites 3.6, which no question uses. Leave it out, and
  add 1.8, 2.1 and 2.2.
* **N2 (Q1):** "spec 8.1's tags" reads as SPEC 8.1, which covers std
  standards. Name the toml test file instead.
* **N3 (Q1):** quote 1.9 exactly: "append to a String or Array
  parameter".
* **N4 (Q1):** estimate how many currently passing defs or benches the
  new rule would refuse.
* **N5 (Q5):** write the nested name `Time::Location::Zone#initialize`.
* **N6 (scope):** TODO section 7 also lists tls, acme/autocert and
  http_https_records (TODO.md:211-225). Say whether they are left out on
  purpose.
* **N7 (structure):** split the draft into three parts:
  * (a) the Q1 checker soundness fix;
  * (b) API reshapes under existing rules (Q1 std, Q3, Q4, Q6);
  * (c) open checker rules (Q2, Q5).
