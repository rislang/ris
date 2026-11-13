# Draft: every ris file ends in .ri, and iyi's names go

Status: draft, EGM reviewed 2026-11-13 (consolidated_review_report.md:
1 Blocker, 9 Major, 3 Minor); section 7 answers each and wins where it
differs from sections 3 to 5. No SPEC.md or code change yet.

## 1. Problem and decided shape

ris has one language, but its files carry two extensions. 328 tracked
files end in `.iyi` (test/cli 132, src/std 121, samples/iyi 37, src/iyi
29, test/speed 7, test/ris 2) beside 698 `.ri` files. The extension
does not say that src/std/atomic.iyi is ris code; the user asked.

Decided by the user (2026-11-13):

1. Every file written in the ris language ends in `.ri`. All 328 files
   are renamed in one job.
2. After it the compiler does not read a `.iyi` file: it refuses it and
   says "rename FILE to FILE.ri".
3. The rename lands before the remaining std-spec module moves
   (doc/drafts/std-spec/), which then work on `.ri` files.
4. iyi's other names that a user of ris meets are renamed too: the
   directories src/iyi/ and samples/iyi/, `iyi.mod`, `IYI_PATH` and the
   like.
5. The line of 3.1 holds: `module Iyi`, src/compiler/iyi/ and the
   `Iyi*` type names stay.

## 2. What exists today

Counts are tracked files outside doc/archive and doc/reference.

* Extension: `.iyi` is written on 5607 lines of 515 files: the
  compiler (81 lines in src/compiler/iyi/*.cr), scripts, CI, Makefile,
  documents and the sources' own comments.
* A source is taken as ris by `filename.ris_source?`
  (src/compiler/crystal_front.cr:56), which picks the prelude
  `iyi/prelude`. The project walk and the spec tools accept both
  extensions (command/project_walk.cr, command/spec_clauses.cr).
* Prelude and runtime: src/iyi/ (29 files), named by the compiler as
  `iyi/prelude` (command.cr:559,990; check.cr:182; doc.cr:252-257;
  daemon.cr:612).
* Samples: samples/iyi/ (37 files) beside samples/ris/. One name
  collides after the rename: hello (samples/iyi/hello.iyi,
  samples/ris/hello.ri).
* Manifest: `ris.mod` is the name; `iyi.mod` is still accepted
  (mod/installer.cr:19-20, check_suite.cr:89,507, spec_clauses.cr:136)
  and `iyi.sum` likewise. 98 lines name iyi.mod, 43 iyi.sum.
* Environment: 1148 lines name an `IYI_*` variable; `IYI_PATH` 539,
  `IYI_CACHE_DIR` 84, `IYI_LIBRARY_PATH` 28, then about 40 more, some
  of them build-time constants (`IYI_CONFIG_PATH`) or runtime symbols
  that only look like variables (`IYI_TL_HANDLE`). ris's own are
  `RIS_*` already (RIS_TAPE_STATS, RIS_JOBS, RIS_PATH once).
* Commands: bin/iyi, bin/iyi.bat, bin/iyi.ps1 beside bin/ris;
  .build/ris is a link to .build/iyi. 378 lines name bin/iyi.
* Internal names: Crystal `module Iyi` (125 files), the directory
  src/compiler/iyi/ (60 lines name it), types `Iyi*` (3537 lines),
  runtime symbols `__iyi_*` (1130 lines).
* AGENTS.md, "Upstream, documents, LLVM": types iyi has keep their
  `Iyi*` names for merges; a type iyi lacks is `Ris*`.
* No file collides on the extension alone: no `X.ri` exists beside an
  `X.iyi`.
* Unmerged work that touches the same files: dev1 holds four moved std
  modules (base64, atomic, bool, box); dev2 and dev4 hold partial
  moves of capsule and colorize.

## 3. Proposed form

### 3.1 The line between renamed and kept

Renamed: what a person writing or running a ris program sees.

* The extension `.iyi` -> `.ri`, every tracked file.
* src/iyi/ -> src/ris/ (the prelude becomes `ris/prelude`).
* samples/iyi/ joins samples/ris/; iyi's hello becomes
  samples/ris/hello_iyi.ri only if it differs in what it shows from
  ris's hello, else it is dropped.
* `iyi.mod`, `iyi.sum`: no longer read. A directory holding one and no
  `ris.mod` fails with "rename iyi.mod to ris.mod".
* Environment variables a user sets: `IYI_X` -> `RIS_X` (IYI_PATH,
  IYI_CACHE_DIR, IYI_LIBRARY_PATH, IYI_MOD_MIRROR, IYI_WORKERS,
  IYI_DAEMON_*, IYI_WASI_CC, IYI_WASMTIME, IYI_EXEC_PATH and the test
  scripts' `IYI=` compiler override, which becomes `RIS=`). A set
  `IYI_X` with no `RIS_X` is not read; the compiler says once on
  stderr "IYI_PATH is not read: set RIS_PATH".
* The command: bin/iyi, bin/iyi.bat and bin/iyi.ps1 are removed;
  .build/ris is the binary, not a link. Messages that say `iyi tool
  format` say `ris ...`.

Kept, because only someone reading the compiler meets them and iyi
merges need them (AGENTS.md's existing rule):

* Crystal's `module Iyi`, the directory src/compiler/iyi/, the build
  constants `IYI_CONFIG_*` and bin/crystal.
* Type names `Iyi*` and runtime symbols `__iyi_*`, and the uppercase
  runtime constants that are not environment variables (IYI_TL_*,
  IYI_SYS_*, IYI_POLL_*, IYI_TC_*, IYI_SG_*).
* doc/archive/ and doc/reference/: inherited documents are not edited.
* The words "iyi" and "iyi SPEC" where a text speaks of the upstream
  project.

### 3.2 The compiler's refusal

* A path ending in `.iyi` given to any verb, found by the project walk,
  or reached by an import fails before parsing:
  "FILE.iyi: a ris file ends in .ri; rename it to FILE.ri".
* `ris_source?` is true for `.ri` only. The project walk lists `.ri`
  only; a `.iyi` file it meets is the error above, not skipped.
* `ris check --fix` does not rename files: a rename is the user's.

### 3.3 Rejected

* Keep reading `.iyi` beside `.ri`: the rule would live in prose, not
  in the compiler (AGENTS.md, "Agent first").
* Rename std and the prelude now, tests later: a half state needs both
  extensions in the compiler and every script.
* Rename `module Iyi`, src/compiler/iyi/ and `Iyi*` types as well: the
  largest part (about 4700 lines), and a renamed identifier conflicts
  whenever iyi touches it. Decided (1.5).

## 4. SPEC.md, AGENTS.md and other documents

* SPEC: a new clause in chapter 6 (the next free number): a ris source
  file ends in `.ri`; the refusal of 3.2; `ris.mod` is the one
  manifest name. SPEC 6.7 loses ".ri or .iyi". Every other clause that
  names a `.iyi` path or an `IYI_*` variable is edited to the new
  name; each such clause's version changes and is listed in the
  CHANGELOG entry.
* AGENTS.md: "Tape first" and "A library works on the caller's tape"
  name `src/iyi/` (exempt from the pointer rule): becomes `src/ris/`.
  One new line under "Upstream": a file from iyi is renamed to `.ri`
  when it is merged.
* README.md, LEARN.md, CONTRIBUTING.md, UPSTREAM.md, TODO.md, LLVM.md,
  doc/drafts/: paths and variable names follow; an EGM drift report
  covers them after the commit.
* doc/drafts/std-spec/DRAFT.md: `MODULE.iyi` reads `MODULE.ri`; the
  baseline script's commit (2739b82d5) stays valid, as it reads only
  src/std/SPEC.md.

## 5. Migration

The work is done in ~/dev/ris-1 on top of the four moved modules.
Partial moves in dev2 and dev4 are kept as patches and redone after.

1. A script (committed as scripts/rename_to_ri.py for this job, removed
   in the last commit) does the mechanical part and can be rerun:
   a. `git mv` every `.iyi` file to `.ri`, src/iyi to src/ris, and the
      samples as 3.1 says;
   b. rewrite in every tracked text file outside doc/archive and
      doc/reference: `.iyi` at a word end -> `.ri`; `src/iyi/` ->
      `src/ris/`; `samples/iyi/` -> `samples/ris/`; `iyi/prelude` ->
      `ris/prelude`; `iyi.mod`/`iyi.sum` -> `ris.mod`/`ris.sum`;
      `bin/iyi` -> `bin/ris`; each renamed variable of 3.1 by an
      explicit list, never by the pattern `IYI_*`;
   c. print every line it left that still holds `iyi` outside the kept
      set of 3.1, for a person to read.
2. By hand: the compiler changes of 3.2, the manifest and environment
   refusals, the Makefile (binary name, install paths `share/iyi`),
   CI, and the lines the script printed.
3. Gates, new, in test/cli: a `.iyi` argument, a `.iyi` file under a
   project, an import reaching a `.iyi` file, a lone `iyi.mod`, a set
   `IYI_PATH`: each refused with its message. And a repository gate:
   `git ls-files '*.iyi'` is empty outside doc/archive and
   doc/reference.
4. Green: the bootstrap build from .build/crystal, `make ris`,
   `bash test/ris/check.sh`, `./bin/ris check spec` (all changed SPEC
   clauses acked after review), the spec_* gates, and every
   test/cli/std_*_exercise.sh that passed before (the 37 of the
   2026-11-13 run, list kept in the commit body) still passes.
5. Commits: one for the rename and rewrite (git shows renames), one
   for the compiler refusals and gates, one for SPEC, AGENTS and the
   documents with the CHANGELOG entry.
6. Other worktrees (dev2, dev3, dev4) and ~/work on minitest are
   rebased or reset onto the result; the user's ~/.local/bin/ris
   launcher and any shell profile setting `IYI_PATH` are the user's to
   change, named in the final report.

## 6. Open points for the review (answered in 7)

* Whether the kept set of 3.1 (internal `Iyi` names) is the right line
  for decision 4 or whether a user meets any of them (error messages,
  `ris doc` output, stack traces showing `__iyi_*`).
* Whether installed layouts (`share/iyi/src`, `lib/iyi`) count as
  user-visible; proposed: yes, they become `share/ris`, `lib/ris`.
* ris-bench and the rispacks keep copies and paths (`samples/ris/
  respond.ri` is copied there): what they must change in step.

## 7. Answers to the EGM review (2026-11-13)

### 7.1 B1: internal names a user does meet

The review showed three kinds on public surfaces. Each gets a rule:

* Text the runtime or compiler prints (the `iyi panic` prefix,
  prelude.iyi:2382; "you've found a bug in the iyi compiler"; `iyi
  tool format` hints; help text): says `ris`. This is text, not an
  identifier, and is rewritten.
* Type names in messages and `ris doc` (`IyiTask(T)` from spawn,
  `IyiIO` behind the alias IO, `IyiWorkers.count`): stay, as the one
  stated exception. AGENTS.md already tells a reader that an `Iyi*`
  type is one iyi has and a `Ris*` type is new; decision 1.5 keeps it.
* Symbols in stack traces (`__iyi_*`): stay, same exception.

Gate: a panic, a refused program and `ris doc` of a sample are run and
their output holds no lowercase word `iyi` outside a type name or a
`__iyi_` symbol.

### 7.2 M1: module artifacts

`.iyimod` -> `.rimod`; `--emit-iyimod`, `--use-iyimod` ->
`--emit-rimod`, `--use-rimod`. The old flags are refused with the new
name. A `.iyimod` file given or found is refused: "built by an older
compiler; rebuild it". Caches are keyed by compiler build already; no
cache is rewritten.

### 7.3 M2: environment variables

The complete list is made first, by the implementer, as a table in this
folder (env-names.md): every `IYI_*` token in the tree, classed as
user variable (renamed), build constant or runtime constant (kept).
Behaviour for a renamed variable X:

| set | result |
| --- | --- |
| RIS_X only | used |
| RIS_X and IYI_X | RIS_X used, no message |
| IYI_X only, non-empty | not used; notice (below) |
| IYI_X empty | as unset |

The notice is one stderr line per variable per run, "IYI_X is not
read: set RIS_X"; the exit status is unchanged. It is a notice, not a
refusal (the word "refused" in 5.3 was wrong):
a stale shell profile must not break every command. The existing
`CRYSTAL_*` fallbacks (config.cr:11-18) are unchanged. `ris env` prints
and accepts the RIS names only. Gate: the table's four rows for
RIS_PATH and RIS_CACHE_DIR, and `ris env`.

### 7.4 M3: what a literal rewrite misses

Changed by hand, each with a regression check that fails if it is
missed: the library-source predicates (util.cr:139-143,
semantic_visitor.cr:518-532), tape mode derived from the prelude path
(compiler.cr:2827-2830), doc's runtime-path test (doc.cr:249-257), the
consumer glob `**/*.[iI][yY][iI]` (check.cr:150-156), and any code that
slices or measures the extension (".iyi".size, [-4..]). The existing
predicates are edited; no second one is added. The suite already
checks tape activation and std's pointer rules (test/ris/check.sh):
its green run is the regression check for the first three.

### 7.5 M4: where a .iyi file is refused

One helper makes the message; every boundary calls it:

| boundary | a `.iyi` file |
| --- | --- |
| a path argument of any verb | refused |
| project walk (test, spec, check, format) | refused, not skipped |
| check_suite's own walk, doc's resolver | refused |
| an import that only a `.iyi` file satisfies | refused, names the file |
| both X.ri and X.iyi present | X.ri used; X.iyi refused when walked |
| `.IYI`, `.Iyi` | refused the same way |
| inside a tree the walk skips (below) | not seen; refused if imported |
| iyi.mod without ris.mod | refused: "rename iyi.mod to ris.mod" |
| iyi.mod beside ris.mod | ris.mod used; iyi.mod refused |
| iyi.sum (N1) | refused: "rename iyi.sum to ris.sum" |

The walk skips lib/, mods/, dot directories, .ris-fixtures trees,
doc/archive and doc/reference. iyi.sum's hash lines have the same
format as ris.sum's, so the rename loses no pin. Each row is a case in
the new gate. A refusal exits 1 before parsing.

### 7.6 M5: installed layout

Old -> new, relative to the install root: bin/iyi -> bin/ris (a file),
bin/iyi-daemon -> bin/ris-daemon, share/iyi/src/iyi ->
share/ris/src/ris, share/iyi/src/std -> share/ris/src/std, share/iyi/
samples and documents -> share/ris/, licenses/iyi -> licenses/ris,
lib/iyi -> lib/ris, and the embedded search paths (Makefile:113,559,
572) follow. `make uninstall` removes the new paths only: an upstream
iyi installed beside ris is not ris's to remove, and a former ris
install's share/iyi is named in the final report for the user. Gate: a
staged `make install DESTDIR=/tmp/...` then hello built and run with
the staged binary from another directory, with no RIS_PATH set, and
the daemon started once.

### 7.7 M6: packages outside the repository

No rispack holds a `.iyi` source or an iyi.mod (review, local trees).
They need only variable names, listed in the review: htmlparse, sha2,
slim, web (check.sh, bench), ricord (bin/test), sqlite (README). These
are changed in each pack's own dev worktree after ris's main holds the
rename, one small commit per pack, its check green with the new
compiler. Until then a pack's check prints 7.3's notice and may fail
to find std: that window is accepted, as nothing is published yet.
ris-bench's iyi row and slim's iyi and Crystal bench modes keep their
`.iyi` inputs and IYI names: they run upstream iyi, not ris.
samples/ris/respond.ri is not changed, so no copy moves.

### 7.8 M7: one landing

The rename, the compiler changes, the gates, SPEC.md with its dated
CHANGELOG entry and the acks land as one commit on dev1: no half state
builds. The rewrite script is a scratch file, never committed. dev1 is
the integration tree.

### 7.9 M8: acceptance, exactly

Before (already recorded): passing-exercises.txt in this folder, the 37
scripts that exited 0 on minitest at 49e76c602 (16 at a time).
After, on minitest in ~/work/ris-1, each must hold:

    export LLVM_CONFIG=$HOME/opt/llvm-23.1.3/bin/llvm-config
    make -j30 ris                      # from the kept .build/crystal
    bash test/ris/check.sh             # "PASS: all ris checks"
    ./bin/ris check spec               # 0 to review, 0 uncovered
    for f in $(cat doc/drafts/ri-extension/passing-exercises.txt)
    do bash "$f" >/dev/null 2>&1 || echo "FAIL $f"; done
    bash test/cli/ri_only.sh           # the new gate (7.1-7.6)
    git ls-files '*.iyi' ':!doc/archive' ':!doc/reference' | wc -l  # 0

The full `ris check` is not the gate: its format part fails on about
298 files on main today, and the user decided (2026-11-13) that the
repository's gate is check.sh plus `ris check spec`.

### 7.10 M9: other worktrees

At implementation time: dev2 (bool, already in dev1; capsule partial),
dev4 (box, already in dev1; colorize partial), dev3 (one commit of its
own, bf9f95924, not in main). Partial module moves are saved as patches
in the lead's scratchpad and redone on `.ri` files, not replayed. dev2
and dev4 hold nothing else, so they are fast-forwarded to the result.
dev3 is not touched by this job: its owner merges main when it resumes.
The user's ~/.local/bin/ris launcher and shell profile are listed in
the final report, not edited.

### 7.11 Minor

N1 is in 7.5; N2 and N3 are fixed in place (3.3, section 1).
