# Draft: the checker and SPEC questions left by the bench port

Status: design draft, reviewed by EGM (2026-11-14,
consolidated_review_report.md) and revised. Not implemented.
Source: TODO.md section 7 ("Left, with their cause"). Each question
names the program that meets it, what the checker does today, the
proposed answer with the clause it touches, its tests and its place in
the order of work. Clauses: SPEC 1.5 (results in the caller's
destination), 1.8 (program data initialization), 1.9 (no implicit copy
back), 2.1 (owners), 2.2 (runtime-sized collections), 3.3 (views and
shrinks).

Gate for every step: `test/ris/check.sh` on minitest 0 FAILED, `ris
check` green, and the bench scan (`RIS_SCOPE_ERRORS=all ris build
--no-codegen` over test/cli/*.ri) not worse than before the step.

## Order of work

1. Q4 and Q5 (std and test changes only; no checker change).
2. Q3 (router storage; std only).
3. Q1's std port (toml, yaml), then Q1's checker fix, in one step: the
   fix refuses today's `RisDecoded(T).new(value).value` (toml.ri:2713,
   yaml.ri:2983), so the port lands first in the same commit.
4. Q2 and Q6 stay open in TODO section 7 until their probes below answer.

## Q1. toml and yaml: `Array(Inner)` through RisDecoded

Today: `TOML.read_value(items[i], T)` for a derived struct `Inner` builds
`RisDecoded(T).new(value).value` in the block round of
`Array(T).new(n) { |i| ... }`. The def ends with `T.new(value)` and
passes the checker, but an `@[OnTape]` struct's `Array` field read back
`[]` in test/cli/std_toml_exercise.ri: the round freed the elements. A
checker hole.

SPEC 2.2 refuses a runtime-sized collection of growing values; an
`Array(Inner)` whose `Inner` has an `Array` field is one. So the answer
is not "build each element in place" but JSON's:

* std: copy json's derive and `JSON.read_into(doc, at, into)`
  (json.ri:374, 4010) to toml and yaml. A derived struct with an Array
  field reads into arrays the caller declares; `read_value(value,
  Array(T))` for such a `T` raises at compile time as json's does
  (json.ri:4006), naming `read_into`. `RisDecoded` is removed (AGENTS: a
  dropped name is removed).
* Checker: a block's value stored by `Array.new(n) { }`, `map` or `<<`
  is a store from the round. When its type holds an owner field (the
  checker's owner notion, TapeOwnerChecker.owner_in, not a list of field
  types) made in the round, refuse with 1.9's sentence ("append to a
  String or Array parameter, ...").
* Tests: test/ris/refused/round_struct_array_field.ri (refused: "cannot
  store data made in this block"); the toml and yaml exercises build and
  their tag checks pass (std_toml_exercise.sh, std_yaml_exercise.sh).

## Q2. zip: the reader blamed for its decoder's refill (open)

Today: `ZipEntryReader` (a class, zip.ri:825) holds `@decoder`, a union
of classes (Inflater, Bzip2Reader, ZstdReader, XzReader; zip.ri:911).
`read` makes the decoder refill its message buffer, and the shrink
checker blames the reader at the next `r.finished?`, also when the read
sits in a def of its own (TODO section 7).

The owner-reference rule of 2026-11-14 (test/ris/owner_reference.ri)
already drops a view whose path passes through an object field, when the
holder is used whole. If the blame remains with that rule in place, the
cause is a view field of `r` that does root in the decoder's buffer, and
the refusal is right (SPEC 3.3).

Probe first: build std_zip_exercise with the rule; if it still fails,
print the view's root (`root_name`). If the root is a field of `r` that
views the decoder's buffer, `ZipEntryReader` must copy what it keeps
(1.7) rather than the checker change. No checker or SPEC change is
proposed until the probe answers. Refused test to keep: a reader holding
a view of its decoder's buffer across `read`
(test/ris/refused/reader_view_across_read.ri).

## Q3. router: patterns kept by the router

Today: `Pattern` is a class with Array fields (router.ri:144, 177): an
owner. `Pattern.parse(text) : Pattern | RouterError` makes one in its
scratch and returns it, which SPEC 2.1 refuses (a def may not return its
own local owner). Routes register through `Router#handle`
(router.ri:551); N patterns as N owners is the shape 2.2 refuses.

Proposal: the router is the one owner. It keeps every pattern's parts in
flat arrays (`@segments : Array(String)` viewing its own `@text`,
`@starts : Array(Int32)` per pattern) and a pattern is an index.
`Router#handle(text, handler) : RouterError?` parses into those arrays.
`Pattern.parse` and the `Pattern` class are removed; `PatternView` (a
struct of index and router) answers what tests asked of a `Pattern`
(`to_s`, `matches?`). The opaque handler call (router.ri:591) is not
part of this step.

Tests: std_router_exercise builds; refused test: a program that keeps a
`PatternView` past its router (test/ris/refused/pattern_view_kept.ri).

## Q4. `File.read_lines`

Today: `read_lines(path) : Array(String)` (file.ri:1674) returns views of
its own read: 1.9 refuses. `File.each_line(path) { |line| }` exists
(file.ri:1703).

Proposal: remove `read_lines` from std/file. Its callers
(test/cli/std_file_exercise.ri, test/cli/io_exercise.ri, the
std_file_exercise.sh patterns, src/std/SPEC.md's mention) move to
`each_line`, appending what they keep to an Array they declare. The
compiler's own `File.read_lines` (src/compiler, Crystal's) is not std's
and is unaffected.

Tests: std_file_exercise builds; `ris check spec` keeps file.7's proof.

## Q5. Time and certificate constants (log, ocsp, x509)

Today: `NOW = Time.utc(2026, 1, 2)` is refused at `Zone#initialize`
(time.ri:743) as request data on the program tape, `.copy_to(Program.
tape)` included; the same value made in a def builds. x509's second
cause: `cert(hex)` returns a Certificate viewing its def's bytes.

SPEC 1.8 governs program data initialization. Classifying
`Zone#initialize`'s stores by caller (a constant initializer versus a
request) needs per-context summaries the program checker does not have.

Proposal: no checker change now. The three tests build their values in
a def called where they are used (or a def that appends into an Array
the caller declares, for certificates), which compiles today; x509's
`cert(hex)` appends into the caller's `Array(Certificate)` (1.5). The
checker change (constant-initializer context for TapeProgramChecker's
`initializer`, tape_program_checker.cr:108) is recorded in TODO section 2
as an open hole, with 1.8 as its clause.

Tests: std_log_exercise, std_ocsp_exercise, std_x509_exercise build.

## Q6. iterator: the opaque callback (open)

Today: `Iterator#to_a` (iterator.ri:225) is `each { |e| result << e }`.
The refusal comes from the adapters, which call their procs
(iterator.ri:549, 565): a proc of a called type is opaque (3.5).
`Enumerable#to_a` (enumerable.ri:56) has the same shape; indexable, set
and slice's `to_a` do not call a proc.

`to_a(into:)` would not help: the append still sits in the opaque block.
Proposal: keep Q6 open; probe which adapter's proc the checker cannot
see through, with a two-line program per adapter (map, select), before
any design. samples/ris/std_iterator.ri does not build either (TODO.md
section 1) and is the probe's acceptance test.

## Out of scope

`User.parse_line`, compress's `--use-rimod` contract and http_resume are
other questions in TODO section 7 and stay there.
