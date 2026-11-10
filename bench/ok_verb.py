#!/usr/bin/env python3
"""`ris ok`: one verdict over fmt, mod tidy, check, vet and test.

    IYI=./bin/ris python3 bench/ok_verb.py

Asserts that a fresh `ris init` project passes with exit 0, that a
misformatted file stops the run at fmt with `next: ris fmt`, that a
failing *_test.ri fails at test with exit 1, that `--json` parses into
the same verdict, that `ris mcp` lists `ok`, and that `ris init` writes
an AGENTS.md and keeps one that is already there.
"""

import json
import os
import subprocess
import sys
import tempfile

IYI = os.path.abspath(os.environ.get("IYI", "./bin/ris"))

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
    return subprocess.run([IYI, *args], capture_output=True, text=True,
                          cwd=cwd, input=stdin)


def main():
    ok_dir = tempfile.mkdtemp(prefix="ris-ok")
    proc = run("init", "hello", cwd=ok_dir)
    agents = os.path.join(ok_dir, "AGENTS.md")
    step("init writes AGENTS.md naming ris ok",
         proc.returncode == 0 and os.path.exists(agents)
         and "`ris ok` passes" in open(agents).read(), proc.stdout)
    proc = run("ok", cwd=ok_dir)
    step("ok passes a clean project with exit 0",
         proc.returncode == 0 and "check  ok" in proc.stdout, proc.stdout)
    with open(os.path.join(ok_dir, "hello.ri"), "w") as f:
        f.write("module hello\n\ndef  f( a )\na\nend\nputs f(1)\n")
    proc = run("ok", cwd=ok_dir)
    step("ok stops at fmt and names ris fmt",
         proc.returncode == 1 and "fmt    FAIL" in proc.stdout
         and "next: ris fmt" in proc.stdout
         and "check" not in proc.stdout.split("next:")[0], proc.stdout)
    run("fmt", "hello.ri", cwd=ok_dir)
    with open(os.path.join(ok_dir, "bad_test.ri"), "w") as f:
        f.write("assert 1 == 2, \"nope\"\n")
    proc = run("ok", cwd=ok_dir)
    step("ok fails at test with exit 1",
         proc.returncode == 1 and "test   FAIL" in proc.stdout
         and "next: fix the failing test" in proc.stdout, proc.stdout)
    proc = run("ok", "--json", cwd=ok_dir)
    try:
        verdict = json.loads(proc.stdout)
    except json.JSONDecodeError:
        verdict = {}
    step("ok --json is the same verdict as data",
         proc.returncode == 1 and verdict.get("ok") is False
         and verdict.get("failed") == "test"
         and [s["name"] for s in verdict.get("steps", [])]
         == ["fmt", "tidy", "check", "vet", "test"]
         and "nope" in (verdict.get("output") or ""), proc.stdout)
    with open(agents, "w") as f:
        f.write("ours\n")
    keep = os.path.join(ok_dir, "keep")
    os.makedirs(keep)
    with open(os.path.join(keep, "AGENTS.md"), "w") as f:
        f.write("ours\n")
    proc = run("init", "keep", cwd=keep)
    step("init keeps an existing AGENTS.md",
         proc.returncode == 0
         and open(os.path.join(keep, "AGENTS.md")).read() == "ours\n",
         proc.stdout + proc.stderr)

    lines = "\n".join([
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                    "params": {"protocolVersion": "2025-06-18"}}),
        json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}),
    ]) + "\n"
    proc = run("mcp", stdin=lines)
    tools = []
    for line in proc.stdout.splitlines():
        reply = json.loads(line)
        if reply.get("id") == 2:
            tools = [t["name"] for t in reply["result"]["tools"]]
    step("mcp lists ok", "ok" in tools, f"{tools}")

    print(f"ok verb gate: {passed} steps held")


if __name__ == "__main__":
    main()
