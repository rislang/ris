#!/usr/bin/env python3
# spec: 6.7@10750e35, 6.8@82707d6b, 6.9@1e0b6a98
"""`ris spec`: the spec's clauses linked to the tests that name them.

    IYI=./bin/ris python3 test/cli/spec_verb.py

Runs the real binary on scratch projects (doc/drafts/spec-cli/spec-cli.md,
Gate). Parsing: SPEC.md and the same spec split in spec/ report alike;
both present fails; continued clauses; heading mismatch and duplicate
numbers fail; a reflow keeps the version, which is Python's SHA-256
prefix; tags with and without version; prose read only without a tag
line; `none (reason)`; one file naming two clauses; `ris spec N.M`;
`--json`; Crystal's verb gone. Versions: a changed text is "to review"
until `ris spec ack`. Check: `ris check spec` and its failures. Todo:
`todo` exits 77, `ris test` and `ris spec todo` report it, an untested
clause fails. Init: `ris init` writes a spec that is green on arrival.
"""

import hashlib
import json
import os
import subprocess
import sys
import tempfile

IYI = os.path.abspath(os.environ.get("IYI", "./bin/ris"))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))

passed = 0


def step(name, ok, detail=""):
    global passed
    print(f"step {passed + 1} {name}: {'ok' if ok else 'FAIL'}")
    if not ok:
        print(detail)
        sys.exit(1)
    passed += 1


def run(*args, cwd):
    env = dict(os.environ, IYI_PATH=os.path.join(REPO, "src"))
    return subprocess.run([IYI, *args], capture_output=True, text=True,
                          cwd=cwd, env=env)


def version(text):
    flat = " ".join(text.split())
    return hashlib.sha256(flat.encode()).hexdigest()[:8]


def write(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def read(root, rel):
    with open(os.path.join(root, rel)) as f:
        return f.read()


C11 = "The blog starts in an empty directory."
C12 = "The posts directory is created\n  when it is missing."
C21 = "Each post has a title."
V11, V12, V21 = version(C11), version(C12), version(C21)

SPEC = (f"# Spec\n\nintro * 9.9 not a clause\n\n## 1. Start\n"
        f"* 1.1 {C11}\n* 1.2 {C12}\n\n## 2. Posts\n* 2.1 {C21}\n")
CHANGELOG = (f"# Changelog\n\n## 2026-11-10 · 1.1@{V11}, 1.2@{V12}\n\n"
             f"Why.\n\n## 2026-11-09 · first\n\n2.1@{V21}\n")


def project(spec=SPEC, changelog=CHANGELOG, tests=None):
    root = tempfile.mkdtemp(prefix="spec-verb-")
    write(root, "ris.mod", "module blog\n")
    write(root, "blog.ri", "module blog\n\nputs \"blog\"\n")
    if spec is not None:
        write(root, "SPEC.md", spec)
    if changelog is not None:
        write(root, "CHANGELOG.md", changelog)
    for rel, text in (tests if tests is not None else {
        "test/start_test.ri":
            f"# spec: 1.1@{V11}\nmodule blog_test\n\nassert true\n",
        "test/posts_test.ri":
            f"# spec: 1.2@{V12}, 2.1@{V21}\n\nassert true\n",
    }).items():
        write(root, rel, text)
    return root


def report(root):
    r = run("spec", "--json", cwd=root)
    if r.returncode != 0:
        step("ris spec --json runs", False, r.stdout + r.stderr)
    return json.loads(r.stdout)


def statuses(root):
    return {c["number"]: c["status"] for c in report(root)["clauses"]}


# ── A: parsing and the report ─────────────────────────────────────────────
def part_a():
    root = project()
    data = report(root)
    step("three clauses, lines outside chapters not read",
         [c["number"] for c in data["clauses"]] == ["1.1", "1.2", "2.1"],
         data)
    vers = {c["number"]: c["version"] for c in data["clauses"]}
    step("versions are SHA-256 prefixes of the normalised text",
         vers == {"1.1": V11, "1.2": V12, "2.1": V21}, vers)
    step("a continued clause is one text",
         data["clauses"][1]["text"] ==
         "The posts directory is created when it is missing.", data)
    step("tagged clauses are ok",
         statuses(root) == {"1.1": "ok", "1.2": "ok", "2.1": "ok"}, data)
    files = data["clauses"][2]["files"]
    step("a file naming two clauses counts for both, shared",
         files == [{"file": "test/posts_test.ri", "version": V21,
                    "todo": None, "own": False}], files)
    step("--json keys", set(data) == {"clauses", "untagged", "counts"} and
         set(data["counts"]) >= {"ok", "todo", "to review", "uncovered",
                                 "unversioned"}, data)

    text = run("spec", cwd=root).stdout
    step("text report ends with the counts",
         text.splitlines()[-1].startswith("3 clauses: 3 ok, 0 todo"), text)

    reflow = SPEC.replace("* 1.2 The posts directory is created\n  when",
                          "* 1.2 The posts directory\n    is created  when")
    write(root, "SPEC.md", reflow)
    step("a reflow keeps the version", statuses(root)["1.2"] == "ok",
         report(root))
    write(root, "SPEC.md", SPEC)

    one = run("spec", "1.2", cwd=root).stdout
    step("ris spec 1.2 shows only 1.2 with its test and changelog",
         one.startswith(f"1.2@{V12} The posts") and "2.1" not in
         one.split("\n")[0] and "test/posts_test.ri (shared, current)"
         in one and "changelog: 2026-11-10" in one, one)
    chap = run("spec", "1", cwd=root).stdout
    step("ris spec 1 shows the chapter",
         "1.1@" in chap and "1.2@" in chap and "2.1@" not in chap, chap)
    bad = run("spec", "3.1", cwd=root)
    step("an unknown clause is refused", bad.returncode != 0 and
         "no clause" in bad.stderr, bad.stderr)

    split = project(spec=None)
    write(split, "spec/1-start.md", SPEC.split("## 2.")[0])
    write(split, "spec/2-posts.md", "## 2." + SPEC.split("## 2.")[1])
    step("a split spec/ reports the same as SPEC.md",
         report(split)["clauses"] == report(root)["clauses"],
         report(split))
    write(split, "SPEC.md", SPEC)
    both = run("spec", cwd=split)
    step("SPEC.md and spec/ both present fail", both.returncode != 0 and
         "both SPEC.md and spec/" in both.stderr, both.stderr)

    for name, spec, want in [
        ("a clause under another chapter's heading fails",
         SPEC.replace("* 2.1", "* 3.1"), "under chapter 2"),
        ("a number written twice fails",
         SPEC + "* 2.1 Again.\n", "written twice"),
    ]:
        r = run("spec", cwd=project(spec=spec))
        step(name, r.returncode != 0 and want in r.stderr, r.stderr)

    prose = project(tests={
        "test/a_test.sh": "#!/bin/sh\n# Checks SPEC 1.1 and SPEC 2.1.\n"
                          "# iyi SPEC 1.2, SPEC 0.1.0\nexit 0\n",
        "test/b_test.py": f"#!/usr/bin/env python3\n# spec: 1.2\n"
                          "# SPEC 2.1 here is not read\n",
        "test/c_test.cr": "# spec: none (implementation: the parser)\n",
        "test/d_test.ri": "assert true\n",
    })
    st = statuses(prose)
    step("prose names clauses unversioned; iyi SPEC and N.M.K not read",
         st == {"1.1": "unversioned", "1.2": "unversioned",
                "2.1": "unversioned"}, report(prose))
    files = [f["file"] for f in report(prose)["clauses"][2]["files"]]
    step("prose is not read in a file with a tag line",
         files == ["test/a_test.sh"], files)
    step("none (reason) is not untagged; a plain test is",
         report(prose)["untagged"] == ["test/d_test.ri"],
         report(prose)["untagged"])
    for name, tag in [("none without a reason is refused", "none"),
                      ("junk after spec: is refused", "1.1 and more"),
                      ("a short version is refused", "1.1@abc")]:
        r = run("spec", cwd=project(tests={"test/x_test.ri":
                                          f"# spec: {tag}\n"}))
        step(name, r.returncode != 0 and "x_test.ri:1" in r.stderr,
             r.stderr)

    help_ = run("spec", "--help", cwd=root)
    step("ris spec --help is the new usage, not Crystal's",
         "ris spec ack N[.M]" in help_.stdout and
         "crystal" not in help_.stdout.lower(), help_.stdout)
    short = run("s", cwd=root)
    step("the s prefix reaches no verb", short.returncode != 0,
         short.stdout + short.stderr)


# ── B: versions and ack ───────────────────────────────────────────────────
def part_b():
    root = project()
    changed = SPEC.replace("Each post has a title.",
                           "Each post has a title and a date.")
    write(root, "SPEC.md", changed)
    st = statuses(root)
    step("a changed clause makes its tags to review",
         st == {"1.1": "ok", "1.2": "ok", "2.1": "to review"}, st)
    one = run("spec", "2.1", cwd=root).stdout
    step("ris spec 2.1 names the stale version",
         f"to review ({V21})" in one, one)
    acked = run("spec", "ack", "2.1", cwd=root)
    new = version("Each post has a title and a date.")
    step("ack rewrites the tag and keeps the other item",
         acked.returncode == 0 and read(root, "test/posts_test.ri")
         .startswith(f"# spec: 1.2@{V12}, 2.1@{new}\n"),
         acked.stdout + acked.stderr + read(root, "test/posts_test.ri"))
    step("after ack the clause is ok", statuses(root)["2.1"] == "ok",
         report(root))

    prose = project(tests={
        "test/a_test.sh": "#!/bin/sh\n# Checks SPEC 1.1 and SPEC 2.1.\n",
        "test/b_test.ri": "# spec: 1.1, 1.2\n# spec: 2.1\nassert true\n",
    })
    run("spec", "ack", "1", cwd=prose)
    a = read(prose, "test/a_test.sh")
    step("ack of a prose file inserts a tag line after #!, keeping 2.1",
         a.startswith(f"#!/bin/sh\n# spec: 1.1@{V11}, 2.1\n# Checks"), a)
    b = read(prose, "test/b_test.ri")
    step("ack N acks the chapter and joins tag lines",
         b == f"# spec: 1.1@{V11}, 1.2@{V12}, 2.1\nassert true\n", b)
    st = statuses(prose)
    step("chapter 1 is ok, 2.1 still unversioned",
         st == {"1.1": "ok", "1.2": "ok", "2.1": "unversioned"}, st)


# ── C: ris check spec ─────────────────────────────────────────────────────
def check(root):
    r = run("check", "spec", cwd=root)
    return r.returncode, r.stdout + r.stderr


def part_c():
    root = project()
    code, out = check(root)
    step("ris check spec passes a clean project",
         code == 0 and out.splitlines()[-1].startswith("3 clauses"), out)

    write(root, "SPEC.md", SPEC.replace("a title.", "a title and a date."))
    code, out = check(root)
    step("a stale tag fails, naming both versions and ack",
         code == 1 and f"test/posts_test.ri tag holds {V21}" in out and
         "spec ack 2.1" in out, out)
    step("the changed clause has no changelog entry either",
         "no CHANGELOG.md entry records 2.1@" in out and
         "next: add `## " in out, out)
    write(root, "SPEC.md", SPEC)

    write(root, "test/x_test.ri", "# spec: 4.4@00000000\n")
    code, out = check(root)
    step("a tag naming no clause fails",
         code == 1 and "test/x_test.ri names 4.4" in out, out)
    os.remove(os.path.join(root, "test/x_test.ri"))

    write(root, "test/x_test.ri", "# spec: what\n")
    code, out = check(root)
    step("a tag that does not parse fails", code == 1 and
         "x_test.ri:1" in out, out)
    os.remove(os.path.join(root, "test/x_test.ri"))

    nolog = project(changelog=CHANGELOG.replace(f"2.1@{V21}", ""))
    code, out = check(nolog)
    step("a version no entry records fails", code == 1 and
         f"no CHANGELOG.md entry records 2.1@{V21}" in out, out)

    bare = project(spec=None, changelog=None)
    r = run("check", cwd=bare)
    lines = [ln.split()[0] for ln in r.stdout.splitlines()
             if ln.split()[:1] and ln.split()[0] in
             ("format", "deps", "spec", "types", "unused", "test")]
    step("ris check: spec after deps, skipped without SPEC.md",
         lines[:3] == ["format", "deps", "spec"] and
         "skip (no SPEC.md)" in r.stdout, r.stdout + r.stderr)
    r = run("check", "spec", "blog.ri", cwd=root)
    step("a PATH skips spec", r.returncode == 0 and
         "a PATH was given" in r.stdout, r.stdout + r.stderr)

    write(root, "SPEC.md", SPEC.replace("a title.", "a title and a date."))
    r = run("check", cwd=root)
    step("ris check fails at spec and names the next command",
         r.returncode == 1 and "next:" in r.stdout, r.stdout + r.stderr)
    write(root, "SPEC.md", SPEC)

    r = subprocess.run([IYI, "mcp"], capture_output=True, text=True,
                       cwd=root, input=json.dumps(
                           {"jsonrpc": "2.0", "id": 1,
                            "method": "tools/list"}) + "\n")
    step("ris mcp lists the spec part",
         '\\"spec\\"' in r.stdout or '"spec"' in r.stdout, r.stdout[:400])


# ── D: todo tests and coverage ───────────────────────────────────────────
def part_d():
    root = project(tests={
        "test/start_test.ri": f"# spec: 1.1@{V11}\nassert true\n",
        "test/posts_test.ri":
            f"# spec: 1.2@{V12}\ntodo \"posts are not created yet\"\n",
    })
    built = os.path.join(root, "todo_bin")
    b = run("build", "test/posts_test.ri", "-o", built, cwd=root)
    r = subprocess.run([built], capture_output=True, text=True)
    step("todo exits 77 and prints its reason",
         b.returncode == 0 and r.returncode == 77 and
         "todo: posts are not created yet" in r.stderr,
         b.stderr + r.stderr + str(r.returncode))
    t = run("test", cwd=root)
    step("ris test reports todo and exits 0",
         t.returncode == 0 and "test/posts_test.ri: todo" in t.stdout and
         "1 passed, 0 failed, 1 todo" in t.stdout, t.stdout + t.stderr)
    j = json.loads(run("test", "--json", cwd=root).stdout)
    step("ris test --json counts todo",
         (j["passed"], j["failed"], j["todo"]) == (1, 0, 1) and
         {x["status"] for x in j["tests"]} == {"pass", "todo"}, j)
    write(root, "test/bad_test.ri", "assert false, \"no\"\n")
    t = run("test", cwd=root)
    step("a failing test beside a todo still fails",
         t.returncode == 1 and "1 passed, 1 failed, 1 todo" in t.stdout,
         t.stdout)
    os.remove(os.path.join(root, "test/bad_test.ri"))

    todo = run("spec", "todo", cwd=root).stdout
    step("ris spec todo lists clause, file and reason",
         "1.2" in todo and "test/posts_test.ri: posts are not created yet"
         in todo and todo.splitlines()[-1] == "1 todo test", todo)
    tj = json.loads(run("spec", "todo", "--json", cwd=root).stdout)
    step("ris spec todo --json", tj == {"todo": [{
        "clauses": ["1.2"], "file": "test/posts_test.ri",
        "reason": "posts are not created yet"}]}, tj)
    code, out = check(root)
    step("2.1 has no proof: ris check spec fails naming it",
         code == 1 and "2.1 has no proof" in out and
         "add `spec 2.1` at the end of the module" in out, out)
    write(root, "test/more_test.ri",
          f"# spec: 2.1@{V21}\ntodo \"later\"\n")
    code, out = check(root)
    step("a todo-only clause passes and is counted",
         code == 0 and statuses(root)["1.2"] == "todo" and
         "2 todo" in out, out)


def part_e():
    base = tempfile.mkdtemp(prefix="spec-verb-init-")
    r = run("init", "example.com/me/hello", "app", cwd=base)
    app = os.path.join(base, "app")
    step("ris init writes SPEC.md, CHANGELOG.md and .spec.lock",
         r.returncode == 0 and all(os.path.exists(os.path.join(app, f))
                                   for f in ("SPEC.md", "CHANGELOG.md",
                                             ".spec.lock")),
         r.stdout + r.stderr)
    r = run("check", cwd=app)
    step("ris check is green on arrival", r.returncode == 0,
         r.stdout + r.stderr)
    statuses_ = statuses(app)
    step("its clause is ok", statuses_ == {"1.1": "ok"}, statuses_)
    own = tempfile.mkdtemp(prefix="spec-verb-own-")
    write(own, "SPEC.md", SPEC)
    run("init", "mine", cwd=own)
    step("an existing SPEC.md is kept and nothing else spec is written",
         read(own, "SPEC.md") == SPEC and
         not os.path.exists(os.path.join(own, "CHANGELOG.md")) and
         not os.path.exists(os.path.join(own, "test")), os.listdir(own))


PARTS = {"A": part_a, "B": part_b, "C": part_c, "D": part_d, "E": part_e}

if __name__ == "__main__":
    wanted = sys.argv[1:] or list(PARTS)
    for letter in wanted:
        PARTS[letter]()
    print(f"spec_verb: {passed} steps passed")
