#!/usr/bin/env python3
"""Every gate in `test/cli/` is reached by something.

    python3 test/cli/gates_reachable.py

A gate that nothing runs is a gate that passes on the machine that wrote it
and nowhere else. This repository has been bitten by that three times in one
release: `format_exercise`, `io_exercise` and `socket_exercise` all existed,
all held, and were named in the workflow by nothing — nine seconds for the
three of them, which is what an unrun gate was saving. `test/cli/panics.sh` was
the fourth, in a narrower form: it ran on Linux and darwin and the sentence
it asserts is Windows' own, so the one platform it was about was the one
platform nothing checked it on.

So this is that lesson, made a check. A script counts as reached when

  * a workflow step names it,
  * another script under `test/cli/` runs or sources it — including
    `test/cli/std_exercise.sh`'s discovery glob, which is how the sixty
    `std_*_exercise.sh` siblings run,
  * the `Makefile` or `Makefile.win` names it, or
  * a script under `scripts/` or a spec names it.

Measured on this tree, the last two arms carry nothing: every reached
script is named by a workflow step or by another script, so the
`Makefile` and `scripts/` arms are there for a way of running a gate that
nothing uses yet rather than for one it relies on. A mention in a target
no job invokes would count as reached, which is the one way this check can
be too generous — worth knowing where the generosity is.

What is left is either a gate nobody runs — the thing to fix — or a *tool*,
which is a different kind of file: it takes an argument and answers a
question a person asked, rather than passing or failing. Those are listed
below with what they are for, and the list is short on purpose: a file that
is neither run nor explained is what this exists to name.

Exits non-zero if anything is unreached and unexplained.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(os.path.dirname(__file__))))
DIRS = {
    name: os.path.join(ROOT, "test", name) for name in ("cli", "speed")
}
REFERENCE = re.compile(r"test/(?:cli|speed)/([A-Za-z0-9_]+\.(?:sh|py))")

# A tool, not a gate: it takes a path and prints a measurement, so there is
# nothing for a job to pass or fail. Each says where its answer is used,
# because "not a gate" is a claim and this is where it is written down.
TOOLS = {
    # `bash test/speed/http2_tape.sh [BASE]` compares std/http and std/hpack
    # before and after their move onto the tape; it measures, it does not
    # hold a line, and speed is measured for the whole project later.
    "http2_tape.sh",
    # `python3 test/speed/tape_memory_svg.py` draws README's tape and heap
    # picture from ris-bench's recorded respond numbers.
    "tape_memory_svg.py",
    # `bash test/speed/ct_timing.sh` times std's secret paths dudect-style and
    # fails loudly past |t| = 10. Run by hand on a quiet machine: on a
    # shared CI runner other jobs' load reaches |t| = 10 with nothing
    # leaking, so no workflow runs it.
    "ct_timing.sh",
    # `python3 test/speed/sibling_times.py LOG...` reads the seconds each std
    # sibling took from a run's std-siblings shard logs. Its numbers are the
    # WEIGHTS `test/cli/std_siblings.sh` deals its shards by; the logs are a
    # run's, downloaded, so there is nothing in a checkout to point it at.
    "sibling_times.py",
    # `bash test/cli/bounded_gate.sh MINUTES GATE [ARGS...]` runs another
    # gate under a time limit; it is a wrapper, with no answer of its own.
    "bounded_gate.sh",
    # These time a cost against a budget or a ratio. A timing never fails
    # a check unless SPEC promises the number (AGENTS.md), and none does;
    # they are run by hand on a quiet machine.
    "defer_cost.sh",
    "definition_typing_scale.py",
    "tls_speed.sh",
}

# A gate that fails on this tree: it stays out of CI until its TODO.md item
# (section 7) is done, and then moves into a workflow step and off this list.
BROKEN = {
    "collections_exercise.sh",
    "collector_free_floor.sh",
    "daemon_agrees.py",
    "debug_info.py",
    "generic_boundary.py",
    "io_exercise.sh",
    "lsp_artifacts.py",
    "lsp_positions.py",
    "mod_context.sh",
    "parallel_exercise.sh",
    "runtime_exercise.sh",
    "socket_exercise.sh",
    "value_exercise.sh",
    "metric_port.sh",
    "rebuild_speed.py",
}


def scripts():
    return {
        f: os.path.join(d, f)
        for d in DIRS.values()
        for f in os.listdir(d)
        if f.endswith((".sh", ".py"))
    }


def text_of(path):
    with open(path, errors="ignore") as handle:
        return handle.read()


def reached(every):
    """Every script something names, and who names it."""
    by = {}

    def note(name, who):
        if name in every:
            by.setdefault(name, set()).add(who)

    workflow = os.path.join(ROOT, ".github", "workflows")
    for directory, _, files in os.walk(workflow):
        for name in files:
            path = os.path.join(directory, name)
            for found in REFERENCE.findall(text_of(path)):
                note(found, os.path.relpath(path, ROOT))

    for name in sorted(every):
        # This script names other scripts in order to explain them, and a
        # mention is not a run: counting its own prose reported the tool
        # below as reached and would report the next unrun gate the same
        # way, as long as somebody had written its name down here.
        if name == os.path.basename(__file__):
            continue
        body = text_of(every[name])
        for found in REFERENCE.findall(body):
            if found != name:
                note(found, os.path.relpath(every[name], ROOT))
        # The discovery glob: `std_exercise.sh` runs every sibling it finds,
        # which is how sixty module exercises reach CI without sixty steps.
        if "std_*_exercise.sh" in body:
            for sibling in every:
                if sibling.startswith("std_") and sibling.endswith("_exercise.sh"):
                    note(sibling, os.path.relpath(every[name], ROOT) + " (discovered)")

    for extra in ("Makefile", "Makefile.win"):
        path = os.path.join(ROOT, extra)
        if os.path.isfile(path):
            for found in REFERENCE.findall(text_of(path)):
                note(found, extra)

    for tree in ("scripts", "test"):
        base = os.path.join(ROOT, tree)
        for directory, _, files in os.walk(base):
            # The scripts' own trees are read above, one script at a time,
            # so a script's mention of itself is not counted as a run.
            if os.path.abspath(directory).startswith(tuple(DIRS.values())):
                continue
            for name in files:
                path = os.path.join(directory, name)
                for found in REFERENCE.findall(text_of(path)):
                    note(found, os.path.relpath(path, ROOT))

    return by


def main():
    every = scripts()
    by = reached(every)
    unreached = sorted(set(every) - set(by))
    unexplained = [n for n in unreached if n not in TOOLS | BROKEN]

    print(f"{len(every)} scripts under test/cli/ and test/speed/, {len(by)} of them reached")
    for name in unreached:
        if name in TOOLS:
            why = "a tool, not a gate"
        elif name in BROKEN:
            why = "fails: see TODO.md"
        else:
            why = "REACHED BY NOTHING"
        print(f"  {name:34s} {why}")

    missing_tools = sorted((TOOLS | BROKEN) - set(every))
    if missing_tools:
        print()
        print("TOOLS names a file that is not there: " + ", ".join(missing_tools))
        print("Remove it from the list, in the same commit as the file.")
        return 1

    named_tools = sorted((TOOLS | BROKEN) & set(by))
    if named_tools:
        print()
        print("TOOLS names a file something runs: " + ", ".join(named_tools))
        print("It is a gate then, so take it off the list — the list is for")
        print("files nothing runs, and an entry that is run hides the next one.")
        return 1

    if unexplained:
        print()
        print("A gate nothing runs passes on the machine that wrote it:")
        for name in unexplained:
            print(f"    {os.path.relpath(every[name], ROOT)}")
        print()
        print("Name it in a workflow job — the job whose platform the gate is")
        print("about — or, if it is a tool rather than a gate, add it to TOOLS")
        print("in this script with what its answer is for, in the same commit.")
        return 1

    print()
    print("every gate under test/cli/ is reached by something that runs it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
