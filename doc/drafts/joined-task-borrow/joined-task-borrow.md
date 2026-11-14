# Draft: a joined task borrows its spawner's value

Status: reviewed by EGM (2026-11-14, consolidated_review_report.md);
revised below. Touches SPEC 5.1.

## Problem

SPEC 5.1 lets a local task capture only Share values, independent copies,
or one value handed off (a socket or pipe end the spawner never names
again). The compiler adds one more exception: a `String` captured by a
task of a `group` block (cleanup_transformer.cr, `check_tape_captures`).

Programs hit the gap where a task needs a value the def already has and
the def does not need it while the task runs:

* std_tls_exercise's `ech_pair`, `captured` and `crafted` run a TLS
  server in a task over the caller's `TlsServerConfig` parameter. The
  config is an owner (not Share) on the caller's tape, so the capture is
  refused ("this block becomes a proc ... is a tape type").
* std_http_https_records's DNS task reads a `UdpSocket` the def opened
  and a `Zone` table the def built. `IyiSocket` and pipe ends may be
  handed off; a `UdpSocket` could not, and a table may not be either.

The refusal's own advice does not help: `copy_to(Program.tape)` of a
config is no way in (Program tape writes need one thread and the copy
outlives the group for nothing), and opening the value inside the task
changes what the test proves.

## Why the capture is safe

Two facts make a borrow by a joined task sound.

1. Lifetime. `group do |g| ... end` returns only after every task it
   spawned ended (5.1, iyi III.4.1). A value of the enclosing def, or a
   parameter (its caller's), outlives the group block.
2. Aliasing. A local task runs on its spawner's thread and switches only
   where it waits (5.6). The borrow is exclusive if, while the group runs,
   no other party reaches the value: the spawner does not name it after
   the spawn inside the group block, no second task captures it, and no
   alias or keeping call was made before the spawn.

That is the hand-off rule (5.1) with one change: the value comes back to
the spawner when the group ends. A hand-off is the case where the task
closes the value; a borrow is the case where it does not.

## Proposal

Amend SPEC 5.1 ("A local task may take one value handed off: ...") with:

> A task of a `group do |g|` block that runs once may borrow one value of
> its enclosing def (a local or a parameter) that is not Share: the task
> captures it, no other task of the group captures it, and the spawner
> neither names it from the spawn to the end of the group block nor kept
> it in an alias or a keeping call before. The value is the spawner's
> again after the group. `spawn_parallel` and `IyiThread.start` may not
> borrow.

The existing hand-off checks (`handed_off?`: aliases, keeping calls, uses
after the spawn, a block that spawns again) apply, with the use scan
ending at the group block's end rather than at the def's end.

`UdpSocket` joins `IyiSocket` and the pipe ends in the hand-off list by
the same rule; it needs no new clause, only the type.

## What does not change

* A thread's block and a parallel task capture Share values only.
* A task still may not assign a captured local (the mutable-cell rule,
  5.1): its answer comes back through `value` or RisBoard.
* Captured `String` stays allowed as today (read-only text).
* `@[TaskClosureUnsafe]` std exceptions stay.

## Checker changes

`taken?(call, captured, meta, type)` decides both checks that see a
local task's capture: `check_tape_captures` (a tape type) and
`check_share_boundary` for `LOCAL_BOUNDARY` (a non-Share type). A
resource (IyiSocket, UdpSocket, the pipe ends) goes to `handed_off?`
as today; any other value goes to `lent?`. Neither applies to
`spawn_parallel` or `IyiThread.start`.

`lent?` walks the variable's scope with `CaptureAssignments`, which now
also records the regions each use sits in. It answers false (the old
refusal stands) unless the spawn sits only in blocks whose one argument
is an `IyiGroup` (the `group` macro's block), and no assignment to the
variable sits inside the outermost such block (a value made in the group,
a `tape do` there included, may end before the task). It raises, naming
the line, on an alias or a keeping call before the spawn (as a hand-off
does) and on any use of the variable inside the group block after the
spawn: the spawner's, or a second task's capture, which the walk sees as
a use. Uses after the group block are the spawner's again.

## Answers to the review

* B1 (UdpSocket already listed): the list held it because this change
  was already in the working tree when the review ran.
* B2 (a task stores its own tape data into the borrowed owner): the tape
  scope checker refuses it already: the task block is a scope, and
  storing what it made into an owner of a wider scope is "cannot store
  data made in this block". Probe: test/ris/refused/borrow_task_store.ri.
* B3 (scope and group not verified): see `lent?` above; a value assigned
  inside the group is refused (refused/borrow_made_in_group.ri). The
  `IyiGroup`-argument test is the one `handed_off?` already relies on;
  only `group` makes such a block in std and programs.
* B4 (`lent?` unspecified): specified above.
* M1 (the caller reaches a parameter by another name): the caller is
  suspended in this def until the group joins; it runs nothing meanwhile.
* M2 (an alias through a field, `tls = config.tls`): such a read is a use
  of `config`; before the spawn it is an alias the walk does not see.
  Known gap, as for hand-offs; the group's tasks are this def's code.
* M3 (closing a borrowed resource): resources are never lent, only handed
  off; closing a lent owner is a method call like any other.
* M4 (a task panics with the value half changed): the spawner gets the
  value as a panicking call would leave it; no tape is freed under it.
* M5 (the task answers the value through `value`): `value` is read in
  the spawner, and the answer names the spawner's own value; once the
  group joins no task holds it, so a second name then is a plain alias
  in one task. Inside the group it is a use and refused.
* M6 (reassignment after the group): still refused, as before; only
  reads come back.
* M7 (second task, loops, nested groups): a second task's capture is a
  use inside the group; a group in a loop joins each round; nested groups
  must all be groups, and the value must be set outside the outermost.
* M8 (one rule, not two): `taken?` is the one entry; resources hand off.
* M9 (where the type list applies): corrected in "Checker changes".
* M10 (SPEC text, messages, tests): below and in the tests list.

## Tests

* test/ris/joined_task_borrow.ri runs: a def passes its owner parameter to
  one task of a group and uses it after the group.
* test/ris/refused/borrow_used_in_group.ri: the spawner reads the value
  inside the group after the spawn: refused, naming the line.
* test/ris/refused/borrow_two_tasks.ri: two tasks of one group capture the
  same value: refused.
* test/ris/refused/borrow_parallel.ri: `spawn_parallel` captures a
  non-Share owner: still refused.
* test/ris/refused/borrow_made_in_group.ri and borrow_task_store.ri
  (B3, B2).
* test/ris/udp_handoff.ri runs: a UdpSocket handed to a task.
* std_tls_exercise builds past `ech_pair`, `captured` and `crafted`'s
  captures; std_http_https_records builds past its UdpSocket task.

## Open questions

* A value reached through the borrowed one (a field of the config) is
  borrowed with it; the spawner naming `config.field` counts as naming
  `config`. The use scan already matches the variable, not its paths.
* Should two tasks share a read-only borrow? Not proposed: telling a read
  from a write of an owner needs an effect summary the checker lacks.
