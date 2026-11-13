#!/usr/bin/env python3
"""`ris check`: one verdict over format, deps, types, unused and test.

    RIS=./bin/ris python3 test/cli/check_verb.py

Runs the real binary on scratch projects and asserts: a clean project
is green with six part lines in fixed order; the no-manifest case
skips deps; a check error beats a failing test; `--fix` fixes a
misformatted file and an extra ris.sum entry, then passes; `-f` equals
`--fix`; `--fix` on a clean project writes no file; `check types
--fix` applies a suggested edit; each removed verb fails as an unknown
command; `--json` carries diagnostics on types; `ris mcp`
lists check and test, not ok or fix; `ris init` writes the AGENTS.md
text and keeps one that is there.
"""

import json
import os
import re
import subprocess
import sys
import tempfile

RIS = os.path.abspath(os.environ.get("RIS", "./bin/ris"))
PARTS = ["format", "deps", "spec", "types", "unused", "test"]
AGENTS_TEXT = ("The work is done when `ris check` passes. Use `ris check "
               "--fix` to fix formatting and dependencies first; `ris check "
               "types` and `ris test --affected FILE` for quick loops.")

passed = 0


def step(name, ok, detail=""):
    global passed
    mark = "ok" if ok else "FAIL"
    print(f"step {passed + 1} {name}: {mark}")
    if not ok:
        print(detail)
        sys.exit(1)
    passed += 1


def run(*args, cwd=None, stdin=None):
    return subprocess.run([RIS, *args], capture_output=True, text=True,
                          cwd=cwd, input=stdin)


def part_lines(out):
    return [ln for ln in out.splitlines()
            if ln.split()[:1] and ln.split()[0] in PARTS]


def order(out):
    return [ln.split()[0] for ln in part_lines(out)]


def snapshot(root):
    found = {}
    for dirpath, _, files in os.walk(root):
        for name in files:
            path = os.path.join(dirpath, name)
            st = os.stat(path)
            found[path] = (st.st_mtime_ns, st.st_size)
    return found


def write(path, text, mode="w"):
    with open(path, mode) as f:
        f.write(text)


def new_project(name):
    root = tempfile.mkdtemp(prefix="ris-check")
    proc = run("init", name, cwd=root)
    assert proc.returncode == 0, proc.stderr
    return root


def main():
    # Spec blocks are callers; an uncalled export still fails unused.
    with tempfile.TemporaryDirectory(prefix="ris-unused-spec-") as bare:
        write(os.path.join(bare, "SPEC.md"),
              "# Spec\n\n## 1. Answer\n\n* 1.1 The answer is 42.\n")
        os.mkdir(os.path.join(bare, "build"))
        src = os.path.join(bare, "build", "unused_spec.ri")
        write(src, "module build/unused_spec\n\n"
              "pub def answer : Int32\n  42\nend\n\n"
              "spec 1.1\n  answer == 42\nend\n")
        proc = run("check", "unused", "build/unused_spec.ri", cwd=bare)
        step("unused counts a spec block as a caller",
             proc.returncode == 0, proc.stdout + proc.stderr)

        write(src, "module build/unused_spec\n\n"
              "pub def answer : Int32\n  42\nend\n\n"
              "pub def unused_answer : Int32\n  7\nend\n\n"
              "spec 1.1\n  answer == 42\nend\n")
        proc = run("check", "unused", "build/unused_spec.ri", cwd=bare)
        step("unused still reports an export with no caller",
             proc.returncode == 1
             and "Build::UnusedSpec#unused_answer" in proc.stdout
             and "Build::UnusedSpec#answer" not in proc.stdout,
             proc.stdout + proc.stderr)

    # The spec build replaces top-level calls into an imported module.
    with tempfile.TemporaryDirectory(prefix="ris-unused-both-") as bare:
        write(os.path.join(bare, "SPEC.md"),
              "# Spec\n\n## 1. Answer\n\n* 1.1 The answer is 42.\n")
        write(os.path.join(bare, "blog.ri"),
              "module blog\n\nimport site::{layout, answer}\n\n"
              "puts layout\n\nspec 1.1\n  answer == 42\nend\n")
        site = os.path.join(bare, "site.ri")
        write(site, "module site\n\n"
              "pub def layout : Int32\n  7\nend\n\n"
              "pub def answer : Int32\n  42\nend\n")
        proc = run("check", "unused", "blog.ri", cwd=bare)
        step("unused keeps plain and spec callers across modules",
             proc.returncode == 0, proc.stdout + proc.stderr)

        write(site, "\npub def unused_page : Int32\n  0\nend\n", "a")
        proc = run("check", "unused", "blog.ri", cwd=bare)
        findings = [ln for ln in proc.stdout.splitlines()
                    if re.search(r"\.ri:\d+:\d+\t", ln)]
        step("unused reports only the uncalled imported def",
             proc.returncode == 1 and len(findings) == 1
             and "Site#unused_page" in findings[0]
             and re.search(r"site\.ri:11:\d+\t", findings[0]),
             proc.stdout + proc.stderr)

    # A library's root exports are proven by the package's other modules.
    with tempfile.TemporaryDirectory(prefix="ris-unused-lib-") as lib:
        write(os.path.join(lib, "SPEC.md"),
              "# Spec\n\n## 1. Answer\n\n* 1.1 The answer is 42.\n")
        write(os.path.join(lib, "ris.mod"), "module example.com/me/lib\n")
        write(os.path.join(lib, "lib.ri"), "module lib\n\n"
              "pub def answer : Int32\n  42\nend\n\n"
              "pub def untested : Int32\n  7\nend\n")
        os.mkdir(os.path.join(lib, "lib"))
        write(os.path.join(lib, "lib", "proofs.ri"),
              "module lib/proofs\n\nimport lib::{answer}\n\n"
              "spec 1.1\n  answer == 42\nend\n")
        proc = run("check", "unused", cwd=lib)
        findings = [ln for ln in proc.stdout.splitlines()
                    if re.search(r"\.ri:\d+:\d+\t", ln)]
        step("unused counts the package's spec blocks as callers",
             proc.returncode == 1 and len(findings) == 1
             and "#untested" in findings[0],
             proc.stdout + proc.stderr)

    # A default initialize the compiler made is not the author's to remove.
    with tempfile.TemporaryDirectory(prefix="ris-unused-init-") as lib:
        write(os.path.join(lib, "SPEC.md"),
              "# Spec\n\n## 1. Greet\n\n* 1.1 Names greet.\n")
        write(os.path.join(lib, "ris.mod"), "module repro\n")
        write(os.path.join(lib, "repro.ri"), "module repro\n\n"
              "pub struct Names\n"
              "  def self.greet(name : String) : String\n"
              "    \"hi #{name}\"\n  end\nend\n\n"
              "pub struct Kept\n  def initialize\n  end\nend\n\n"
              "pub def unwritten_caller : Int32\n  7\nend\n\n"
              "spec 1.1\n  Names.greet(\"x\") == \"hi x\"\nend\n")
        proc = run("check", "unused", cwd=lib)
        findings = [ln for ln in proc.stdout.splitlines()
                    if re.search(r"\.ri:\d+:\d+\t", ln)]
        step("unused skips a generated initialize, keeps a written def",
             proc.returncode == 1 and len(findings) == 2
             and "Kept#initialize" in findings[0]
             and "#unwritten_caller" in findings[1],
             proc.stdout + proc.stderr)

    root = new_project("hello")
    agents = os.path.join(root, "AGENTS.md")
    text = " ".join(open(agents).read().split())
    step("init writes the new AGENTS.md text", AGENTS_TEXT in text, text)

    proc = run("check", cwd=root)
    lines = proc.stdout.splitlines()
    step("clean project green, six part lines in order",
         proc.returncode == 0 and order(proc.stdout) == PARTS
         and re.fullmatch(r"ok in \d+\.\ds", lines[-1]), proc.stdout)
    step("each run part line ends in its time",
         all(re.search(r" \d+\.\ds$", ln) for ln in part_lines(proc.stdout)
             if " skip" not in ln), proc.stdout)

    before = snapshot(root)
    proc = run("check", "--fix", cwd=root)
    step("check --fix on a clean project writes no file",
         proc.returncode == 0 and snapshot(root) == before,
         proc.stdout + proc.stderr)

    proc = run("check", "--json", cwd=root)
    verdict = json.loads(proc.stdout or "{}")
    steps = verdict.get("steps", [])
    types = [s for s in steps if s["name"] == "types"]
    step("--json shape: steps named by part, diagnostics on types",
         verdict.get("ok") is True
         and [s["name"] for s in steps] == PARTS
         and types and types[0].get("diagnostics") == []
         and isinstance(verdict.get("seconds"), (int, float))
         and set(verdict) >= {"ok", "steps", "failed", "output", "next"},
         proc.stdout)

    # No manifest: deps skips.
    bare = tempfile.mkdtemp(prefix="ris-check-bare")
    write(os.path.join(bare, "app.ri"), "puts 1\n")
    proc = run("check", cwd=bare)
    deps = [ln for ln in part_lines(proc.stdout) if ln.startswith("deps")]
    step("no manifest: deps skips, the rest is green",
         proc.returncode == 0 and order(proc.stdout) == PARTS
         and deps and "skip" in deps[0], proc.stdout)
    proc = run("check", "deps", cwd=bare)
    step("a named part with nothing to do says skip, exit 0",
         proc.returncode == 0 and "skip" in proc.stdout, proc.stdout)

    # --fix: a misformatted file and an extra ris.sum entry.
    for flag in ("--fix", "-f"):
        fixme = new_project("fixme")
        src = os.path.join(fixme, "fixme.ri")
        # init's spec 1.1 stays proved, so only format and ris.sum fail.
        write(src, "module fixme\n\ndef  f( a )\na\nend\n"
              "puts \"hello from #{f(\"fixme\")}\"\n\n"
              "spec 1.1\n  fixme == \"hello from fixme\\n\"\nend\n")
        sum_path = os.path.join(fixme, "ris.sum")
        write(sum_path, "example.com/gone v1.0.0 s1:abc\n", "a")
        proc = run("check", cwd=fixme)
        step(f"before {flag}: format fails, next names ris check --fix",
             proc.returncode == 1 and "format FAIL" in proc.stdout
             and "next: ris check --fix" in proc.stdout, proc.stdout)
        proc = run("check", flag, cwd=fixme)
        step(f"check {flag} fixes format and ris.sum, then passes",
             proc.returncode == 0
             and "def f(a)" in open(src).read()
             and "example.com/gone" not in open(sum_path).read(),
             proc.stdout + proc.stderr)

    # types --fix applies a suggested edit.
    typo = new_project("typo")
    src = os.path.join(typo, "typo.ri")
    write(src, "module typo\n\ndef greet : String\n  \"hi\"\nend\n\n"
               "puts gret\n\nspec 1.1\n  todo \"prints hello\"\nend\n")
    proc = run("check", "--json", cwd=typo)
    verdict = json.loads(proc.stdout or "{}")
    types = [s for s in verdict.get("steps", []) if s["name"] == "types"]
    step("--json carries the suggested edit under types diagnostics",
         verdict.get("failed") == "types" and types
         and any(d.get("suggested_edit", {}).get("replacement") == "greet"
                 for d in types[0].get("diagnostics", []))
         and verdict.get("next") == "ris check types --fix", proc.stdout)
    proc = run("check", "--fix", cwd=typo)
    step("check --fix leaves types edits alone",
         proc.returncode == 1 and "puts gret\n" in open(src).read()
         and "next: ris check types --fix" in proc.stdout, proc.stdout)
    proc = run("check", "types", "--fix", cwd=typo)
    step("check types --fix applies the suggested edit",
         proc.returncode == 0 and "puts greet\n" in open(src).read(),
         proc.stdout + proc.stderr)

    # Fixed order: a check error beats a failing test.
    par = new_project("par")
    for i in range(3):
        write(os.path.join(par, f"t{i}_test.ri"), "assert 1 == 1, \"fine\"\n")
    proc = run("check", "-j", "2", cwd=par)
    step("-j passes several tests; parts in fixed order",
         proc.returncode == 0 and order(proc.stdout) == PARTS
         and "test   ok" in proc.stdout, proc.stdout + proc.stderr)
    write(os.path.join(par, "t9_test.ri"), "assert 1 == 2, \"nope\"\n")
    proc = run("check", cwd=par)
    step("a failing test fails at test",
         proc.returncode == 1 and "test   FAIL" in proc.stdout
         and "next: fix the failing test" in proc.stdout, proc.stdout)
    # Above init's spec section: code may not follow the first block.
    par_src = os.path.join(par, "par.ri")
    text = open(par_src).read()
    write(par_src, text.replace("\nspec ", "\nundefined_thing_here\n\nspec ", 1))
    proc = run("check", "-j", "4", cwd=par)
    step("a check error and a failing test: types is the failure",
         proc.returncode == 1 and "types  FAIL" in proc.stdout
         and order(proc.stdout)[:4] == ["format", "deps", "spec", "types"]
         and all(ln.endswith("stopped") for ln in part_lines(proc.stdout)
                 if ln.startswith(("unused", "test")))
         and "next: ris check types --fix" in proc.stdout, proc.stdout)

    # Removed verbs: gone, failing as an unknown command does.
    unknown = run("nosuchverb", cwd=root)
    removed = [["ok"], ["vet"], ["fmt"], ["fmt", "--check"], ["format"],
               ["mod", "tidy"], ["mod", "tidy", "--check"],
               ["fix", "x.ri"], ["tool", "format"],
               ["tool", "unreachable"]]
    for args in removed:
        proc = run(*args, cwd=root)
        step(f"ris {' '.join(args)} fails as an unknown command",
             proc.returncode != 0 and unknown.returncode != 0
             and "ris check" not in proc.stdout + proc.stderr
             and "unknown" in proc.stderr, proc.stdout + proc.stderr)
    proc = run("check", "-f", "json", cwd=root)
    step("check -f json is refused naming --json",
         proc.returncode != 0 and "--json" in proc.stderr, proc.stderr)
    proc = run("check", cwd=root)
    step("bare ris check is green",
         proc.returncode == 0, proc.stdout + proc.stderr)

    # MCP tool list.
    lines = "\n".join([
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                    "params": {"protocolVersion": "2025-06-18"}}),
        json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}),
        json.dumps({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                    "params": {"name": "check",
                               "arguments": {"part": "types"}}}),
    ]) + "\n"
    proc = run("mcp", cwd=root, stdin=lines)
    tools = []
    call = None
    for line in proc.stdout.splitlines():
        reply = json.loads(line)
        if reply.get("id") == 2:
            tools = [t["name"] for t in reply["result"]["tools"]]
        if reply.get("id") == 3:
            call = reply["result"]
    step("mcp lists check and test, not ok or fix",
         "check" in tools and "test" in tools
         and "ok" not in tools and "fix" not in tools, f"{tools}")
    body = json.loads(call["content"][0]["text"]) if call else {}
    step("mcp check part=types returns the steps object",
         call and call["isError"] is False and body.get("ok") is True
         and body["steps"][0].get("diagnostics") == [], f"{call}")

    write(agents, "ours\n")
    keep = os.path.join(root, "keep")
    os.makedirs(keep)
    write(os.path.join(keep, "AGENTS.md"), "ours\n")
    proc = run("init", "keep", cwd=keep)
    step("init keeps an existing AGENTS.md",
         proc.returncode == 0
         and open(os.path.join(keep, "AGENTS.md")).read() == "ours\n",
         proc.stdout + proc.stderr)

    print(f"check verb gate: {passed} steps held")


if __name__ == "__main__":
    main()
