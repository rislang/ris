# Goldfish Review Report

**Target:** `doc/drafts/joined-task-borrow/joined-task-borrow.md` (whole)

Verdict: not ready. Four Blockers, ten Majors. The lifetime idea (the group
joins before the spawner continues) holds, but the draft's premises are
partly stale, the return path is unsound, and `lent?` is not specified.

## Reviewer Status

| Reviewer | Status |
| --- | --- |
| `design` | completed |
| `codebase-details` | completed |
| `implementation-readiness` | completed |
| `zoom-out` | completed |

Reviewers read the draft, SPEC.md 5.1 and cleanup_transformer.cr. None read
AGENTS.md in full; rule fit was judged from the task's summary.

## Blockers

### B1. UdpSocket is already a hand-off type
* **Lens:** codebase-details, implementation-readiness, zoom-out
* **Scope:** Problem bullet 2; Proposal last paragraph; Checker changes 3
* **Description:** `Std::Udp::UdpSocket` is already in the hand-off list
  (cleanup_transformer.cr:813, file not modified). The stated cause of the
  std_http_https_records refusal is wrong; Checker change 3 is a no-op.
* **Recommendation:** Reproduce the real error and line, restate the
  cause (likely a use after the spawn or check_share_boundary), and drop
  item 3. Until then the draft rests on one case (`TlsServerConfig`).

### B2. A task can store its own tape data into the borrowed value
* **Lens:** zoom-out, codebase-details
* **Scope:** Why the capture is safe; Proposal
* **Description:** A hand-off never comes back; a borrow does. The task
  can write a String or Array built on its tape into a field of the
  borrowed owner. The task's tape is freed when it ends, so after the
  group the spawner reads dangling data. This breaks 5.1 ("owners are
  built on their task's tape"). The draft argues only lifetime and
  aliasing, not what flows back.
* **Recommendation:** Choose and specify one: borrow only types that
  cannot hold tape values (resource handles); require `copy_to` the
  value's owner for every store; or require read-only use (needs an
  effect summary). Name the check that refuses it; add a refused test.

### B3. The value's scope and the joining group are not verified
* **Lens:** design, zoom-out
* **Scope:** Why the capture is safe, point 1
* **Description:** "A value of the enclosing def outlives the group" is
  false for a local made in a `tape do` block inside the group: the task
  may outlive that tape. Also, `handed_off?` accepts any block whose one
  argument is an `IyiGroup` (lines 1017-1020); a method that yields a
  group it does not join on exit would pass, and the spawner would reuse
  the value while the task runs.
* **Recommendation:** Require that the region is the block of a `group`
  call that joins on exit, and that the value's `meta.context` and tape
  strictly enclose that call. Add refused tests for both.

### B4. `lent?` is not specified
* **Lens:** implementation-readiness, codebase-details
* **Scope:** Checker changes 1-2
* **Description:** There is no "use scan ending at the def's end" to
  shorten: `CaptureAssignments` walks `meta.context.body` and records
  every read after the spawn (1532-1674). The draft does not say how the
  group call is found, how the walk stops at it, whether the alias and
  keeping-call scans stay unbounded, whether `lent?` raises or returns
  false, or its precedence against `handed_off?` at line 910.
* **Recommendation:** Give the algorithm: how the enclosing group is
  found, the stop node for `CaptureAssignments`, raise vs. return, the
  order with `handed_off?`, and the new error strings ("borrowed until
  the group ends at line N", not "the task owns it now").

## Majors

### M1. Parameters may be aliased by the caller
* **Lens:** design, implementation-readiness
* **Scope:** Why the capture is safe, point 2
* **Description:** The scan sees only the def's own names. A parameter
  may be reachable through `f(x, x)`, a field of `self` or another
  parameter, a constant or class variable, while the spawner waits and
  other tasks of the group run.
* **Recommendation:** Borrow only def-local values with visible creation,
  or prove from 5.1 that no other running task can reach the alias and
  state it in SPEC.

### M2. Part-aliases escape the scan
* **Lens:** design, zoom-out
* **Scope:** Open questions 1
* **Description:** `tls = config.tls` before the spawn, used by the
  spawner or a second task, is not caught: `CaptureAssignments.aliases`
  (1004) sees whole-variable copies only.
* **Recommendation:** Treat any local assigned from a path rooted at the
  borrowed variable as an alias. Move the `config.field` rule from Open
  questions into the Proposal; add refused tests.

### M3. Closing or consuming a borrowed value
* **Lens:** design, implementation-readiness
* **Scope:** Why the capture is safe, last paragraph; SPEC 5.6
* **Description:** The check cannot tell a borrow from a hand-off. A task
  may close a borrowed socket; the spawner then uses it after the group.
  5.6 ("opened, used and closed by the same task") is strained.
* **Recommendation:** Refuse closing calls in the task, keep resources
  hand-off only, or define the runtime error. Amend 5.6.

### M4. Task panic leaves a broken value
* **Lens:** design
* **Scope:** Proposal
* **Description:** The group catches a task panic (4.1); the spawner gets
  back a value with broken invariants.
* **Recommendation:** Specify the behaviour (value unusable, or panic
  propagates) and test it.

### M5. Answering the borrowed value through `value`
* **Lens:** implementation-readiness
* **Scope:** Why the capture is safe
* **Description:** The task can answer the value, or a path into it,
  creating a second handle the spawner holds beside the original.
* **Recommendation:** Decide (likely refuse) and test.

### M6. Reassignment after the group is still refused
* **Lens:** codebase-details
* **Scope:** What does not change, bullet 2
* **Description:** `check_thread_capture_assigned_once` (916, 1055-1093)
  refuses any assignment after the spawn for a mutably closured variable,
  not just inside the group. "The spawner's again" holds only for reads.
* **Recommendation:** Say so, or include that function in the change.

### M7. Second-task detection and loops/nested groups are unspecified
* **Lens:** implementation-readiness, zoom-out, codebase-details
* **Scope:** Checker changes 1; Proposal
* **Description:** No index maps a group to its spawns; the draft does not
  name one. A group in a loop is sound for a borrow, but `start_regions`
  refuses it; nested groups and a task that spawns again are not covered.
  The existing use scan may already refuse a second task (1658-1661).
* **Recommendation:** Confirm with `borrow_two_tasks`; if needed name the
  structure. State the region rule for borrows and test loop, nested
  group and re-spawn from inside the task.

### M8. One rule, not two
* **Lens:** zoom-out, design
* **Scope:** Proposal; Checker changes
* **Description:** A hand-off is a borrow the task closes. A separate
  `lent?` beside `handed_off?` plus a type allowlist gives an agent two
  overlapping rules and two error sets.
* **Recommendation:** Widen `handed_off?` (scan ends at the group, one
  task per value) and rewrite the existing 5.1 sentence rather than add a
  paragraph. If kept separate, give it its own messages (see B4).

### M9. Problem section misplaces the type restriction
* **Lens:** codebase-details, implementation-readiness
* **Scope:** Problem para 1; Checker changes 2
* **Description:** `check_share_boundary` already accepts any non-Share
  capture when `handed_off?` holds (910). The type list applies only to
  tape-typed captures in `check_tape_captures` (813-818). Change 2 only
  widens line 910.
* **Recommendation:** Restate both paragraphs accordingly.

### M10. SPEC text, messages and tests are under-specified
* **Lens:** implementation-readiness, design
* **Scope:** Proposal; Tests
* **Description:** No exact SPEC 5.1 location or wording, no new
  `LOCAL_BOUNDARY.consequence` / refusal text (still "Share values
  only"), no expected error substrings, no check.sh registration, no
  expected output, no named test/cli proof for the std claims.
  Missing cases: alias and keeping call before the spawn, use after the
  group (passes), field use in the group, part-alias, nested-tape value,
  close-then-use, group in loop, nested group, `IyiThread.start` refused,
  self/ivar capture.
* **Recommendation:** List each test as Create with file, expected
  stdout or error substring and harness entry; give the SPEC diff and a
  `spec 5.1` proof block plan.

## Minors

* **m1** Proposal: "may borrow one value" is ambiguous (per task or per
  group); state "each value is borrowed by at most one task". (design)
* **m2** What does not change: say `self` and instance variables are not
  borrowable (`self` check at 926). (design)
* **m3** What does not change: mention the `@[TaskClosureUnsafe]` bypass
  (812, 852) and that the String exception needs `@joined_task_blocks`
  (809). (codebase-details)
* **m4** String captures: say whether a borrow changes the unconditional
  String rule. (implementation-readiness)
* **m5** Checker changes: the helper signature is more detail than the
  design needs; state rule and changed checks. (zoom-out)
* **m6** Tests: mark each new file Create. (codebase-details)
