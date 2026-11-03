#!/usr/bin/env python3
"""Run test/ris/check.sh's blocks on every core, output in file order.

check.sh stays the one list of checks. Its header (settings and the
expect helper) runs before each block; the blocks are its top-level
statements (see split), so a block must not read a variable
another block set. heap_check.py runs after all parallel jobs finish.
Each job gets its own TMPDIR and compiler cache (IYI_CACHE_DIR). A job
that runs past RIS_CHECK_TIMEOUT seconds (default 300) is killed with
its processes and reported FAILED, so one hung test cannot hold the
suite.
RIS_CHECK_SERIAL=1 bash test/ris/check.sh runs it in order.
RIS_CHECK_MATCH selects blocks by regex and skips unrelated heap workloads.
RIS_CHECK_SKIP drops blocks by regex: a trial target's Linux-only checks.
RIS_CHECK_SHARD=k/n runs every n-th block from the k-th (1-based) and no
heap gate; RIS_CHECK_SHARD=heap runs the heap gate alone. CI runs the n
block shards and the heap shard as separate jobs.
"""
import concurrent.futures
import os
import re
from pathlib import Path
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "test/ris/check.sh"


def split():
    lines = SCRIPT.read_text().splitlines()
    end = lines.index("}") + 1  # the expect helper closes the header
    # Drop the cd: jobs run in ROOT. The heap gate stays outside the pool.
    header = [line for line in lines[:end] if not line.startswith("cd ")]
    stop = lines.index(
        "# Run heap workloads after the other gates to avoid compiler contention."
    )
    # A block starts at a top-level comment, `out=$(`, `expect` or `for`
    # once every `if`/`for`/`while`/`case` and quote above it is closed.
    blocks, block, depth, quoted = [], [], 0, False
    for line in lines[end:stop]:
        starts = line.startswith(
            ("#", "out=$(", "result=$(", "expect ", "for "))
        if not line.strip():
            continue
        # A `for` right after `out=$(` reads that output: keep them together.
        reads = line.startswith("for ") and block and \
            block[-1].startswith("out=$(")
        if starts and not reads and depth == 0 and not quoted and block and \
                not block[-1].startswith("#"):
            blocks.append(block)
            block = []
        block.append(line)
        word = line.split(" ", 1)[0].rstrip(";")
        closed = line.rstrip().endswith(("fi", "done", "esac"))
        if word in ("if", "for", "while", "case") and not closed:
            depth += 1
        elif word in ("fi", "done", "esac"):
            depth -= 1
        # `python3 -c '` opens a multi-line single-quoted program.
        odd = line.count("'") % 2
        if quoted and odd or "python3 -c '" in line and odd:
            quoted = not quoted
    if block:
        blocks.append(block)
    return header, blocks


def run(header, block, scratch, index):
    tmp = Path(scratch) / f"job-{index}"
    tmp.mkdir()
    script = tmp / "check.sh"
    script.write_text("\n".join(header + block + ['exit "$status"']) + "\n")
    # A compiler cache of its own: two jobs building one .ri (variants of
    # a gate) shared ~/.cache/iyi/<path> and raced on its object files.
    env = dict(os.environ, TMPDIR=str(tmp), RIS_CHECK_SERIAL="1",
               IYI_CACHE_DIR=str(tmp / "cache"))
    limit = int(os.environ.get("RIS_CHECK_TIMEOUT", "300"))
    job = subprocess.Popen(["bash", str(script)], cwd=ROOT, env=env,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, start_new_session=True)
    try:
        out, _ = job.communicate(timeout=limit)
        return job.returncode, out
    except subprocess.TimeoutExpired:
        os.killpg(job.pid, signal.SIGKILL)
        out, _ = job.communicate()
        first = next((line for line in block if line.strip()), "")
        return 1, f"{out}FAILED   timeout after {limit}s: {first.strip()}\n"


def heap(scratch):
    env = dict(os.environ, TMPDIR=scratch)
    done = subprocess.run([sys.executable, "test/ris/heap_check.py"],
                          cwd=ROOT, env=env, capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


def main():
    header, blocks = split()
    # Select checks without running unrelated workloads or the heap suite.
    pattern = os.environ.get("RIS_CHECK_MATCH")
    if pattern:
        blocks = [block for block in blocks
                  if re.search(pattern, "\n".join(block), re.MULTILINE)]
        if not blocks:
            print("FAIL: no ris checks match RIS_CHECK_MATCH")
            return 1
    skip = os.environ.get("RIS_CHECK_SKIP")
    if skip:
        blocks = [block for block in blocks
                  if not re.search(skip, "\n".join(block), re.MULTILINE)]
    shard = os.environ.get("RIS_CHECK_SHARD", "")
    if shard == "heap":
        blocks = []
    elif shard:
        k, n = (int(part) for part in shard.split("/"))
        if not 1 <= k <= n:
            print(f"FAIL: RIS_CHECK_SHARD={shard} is not k/n with 1 <= k <= n")
            return 1
        blocks = blocks[k - 1::n]
    workers = int(os.environ.get("RIS_CHECK_JOBS", os.cpu_count() or 1))
    with tempfile.TemporaryDirectory(prefix="ris-check-") as scratch:
        with concurrent.futures.ThreadPoolExecutor(workers) as pool:
            jobs = [pool.submit(run, header, block, scratch, index)
                    for index, block in enumerate(blocks)]
            status = 0
            for job in jobs:
                code, out = job.result()
                sys.stdout.write(out)
                sys.stdout.flush()
                status |= code != 0
        if not pattern and (not shard or shard == "heap"):
            code, out = heap(scratch)
            sys.stdout.write(out)
            sys.stdout.flush()
            status |= code != 0
    label = "selected ris checks" if pattern else "all ris checks"
    if shard:
        label = f"ris checks, shard {shard}"
    print(f"PASS: {label}" if status == 0 else f"FAIL: {label}")
    return status


if __name__ == "__main__":
    sys.exit(main())
