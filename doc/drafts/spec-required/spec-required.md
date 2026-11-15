# Draft: a project always has a SPEC, a public def always a proof

Status: amended after EGM review (2026-11-15,
[consolidated_review_report.md](consolidated_review_report.md));
ready for SPEC and code.

Context: SPEC 6.8 lists what `ris check spec` fails on; check_suite.cr
skips the part with "no SPEC.md". A clause with no proof already fails.
What does not fail: a project with no spec, and a new public def that
no spec block proves. An agent follows errors, not prose (AGENTS.md),
so both gaps let it write code with no clause.

## 1. Decisions (made by the user; not reopened here)

D1. A project with no spec fails `ris check spec`; it is no longer
skipped.

D2. A public def that no spec block proves fails `ris check spec`.

D3. A change that adds no public def needs no clause (refactor, speed,
test fix): nothing here asks for one.

## 2. Rules

R1 (D1). The root is `spec_root`'s (nearest `ris.mod`, else the
cwd). "No spec" is zero clauses of any kind under the root: no
SPEC.md, no spec/*.md, no module clause. Then `ris check spec`
fails and prints the form itself (not `ris init`, which refuses
when `ris.mod` exists):

    no spec: write SPEC.md with a clause
      * 1.1 TEXT
    and prove it at the end of the root module
      spec 1.1
        EXPR == VALUE
      end

A PATH argument still skips the part, as today.

R2 (D2). A def is public unless it is `private` or `protected`, a
`lib` fun, or in an `@[Ffi]` file or type. No path condition. Generated
defs (macro expansions, `property` and kin) are exempt: the written
line is a macro call; a project macro making API is a known hole.

R3. Proof sits in the def's own module (spec-blocks D4: the module
is the test unit). A public def is covered when a spec block at the
end of its file names it on an assertion line (a top-level Bool
line, D3 of spec-blocks), or the block holds `todo` and names it on
any line. The match is textual: `.name(`, `.name ` or `&.name` for
`def name` and `def self.name`; `initialize` is covered by `.new`;
an operator def by the operator between operands or `[`. One name
covers all its overloads and both receivers: a deliberate hole that
keeps the check text-only and fast; an abstract def is covered by
its own name.

R4. An uncovered public def fails at file:line with the safe form:

    post.ri:12: public def slugify has no proof; add at the end
      spec N.M
        Post.slugify("...") == "..."
      end
    or `todo "reason"` inside it, `@[NoSpec("reason")]`, or private

R5. `@[NoSpec("reason")]` goes on a def or on a module header; on a
module it covers the public defs the module has when the mark is
written and `ris spec ack --nospec MODULE` records their names in
.spec.lock. A public def added later still fails (a ratchet). An
empty reason fails: "NoSpec needs a reason". It lifts no safety
rule, so `ris unsafe` does not list it. A mark as the file's first
code line, followed by a blank line or by no def, is the module's;
right above a def it is the def's. A module mark not yet acked fails:
"run `ris spec ack --nospec PATH`". Defs below the first spec block
are test helpers and are not checked; `ris spec todo` lists each
mark with its reason and count.

R6 (added 2026-11-15 after the drift report was skipped once). A
CHANGELOG.md entry dated 2026-11-15 or later that names a
doc/drafts/ folder fails `ris check spec` until that folder holds a
`*_DRIFT_REPORT.md`; older entries are left as they are.

## 3. Rollout

S1. SPEC 6.8 gains R1-R5; CHANGELOG entry names this folder and
tells rispacks to run `ris check spec`.
S2. Code in spec_clauses.cr / check_suite.cr. test/cli/ script runs
the real `ris check spec` on fixtures with expected stderr and exit:
no spec; module clauses only (passes); uncovered def (R4 text);
private, protected, lib, @[Ffi] (pass); todo cover; `&.name`;
`.new`; operator; call only off an assertion line (fails);
cross-module call only (fails); NoSpec def, module, empty reason;
def added under a module NoSpec (fails); `property` (passes).
S3. One series: ris tree and samples get blocks, todos or module
NoSpec marks first, then the error turns on in the same push; the
mark count goes in the commit body.
