#!/usr/bin/env python3
"""Run test/ris/check.sh's blocks on every core, output in file order.

check.sh stays the one list of checks. Its header (settings and the
expect helper) runs before each block; the blocks are its top-level
statements (see split), so a block must not read a variable
another block set. heap_check.py runs as one more job. Each job gets its
own TMPDIR. RIS_CHECK_SERIAL=1 bash test/ris/check.sh runs it in order.
"""
import concurrent.futures
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "test/ris/check.sh"


def split():
    lines = SCRIPT.read_text().splitlines()
    end = lines.index("}") + 1  # the expect helper closes the header
    # Drop the cd (jobs run in ROOT) and the serial run's heap start.
    first = lines.index("heap_log=$(mktemp)")
    last = lines.index("heap_pid=$!")
    header = [l for i, l in enumerate(lines[:end])
              if not l.startswith("cd ") and not first <= i <= last]
    stop = lines.index('wait "$heap_pid" || status=1')
    # A block starts at a top-level comment, `out=$(`, `expect` or `for`
    # once every `if`/`for`/`while`/`case` and quote above it is closed.
    blocks, block, depth, quoted = [], [], 0, False
    for line in lines[end:stop]:
        starts = line.startswith(("#", "out=$(", "expect ", "for "))
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
    env = dict(os.environ, TMPDIR=str(tmp), RIS_CHECK_SERIAL="1")
    done = subprocess.run(["bash", str(script)], cwd=ROOT, env=env,
                          capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


def heap(scratch):
    env = dict(os.environ, TMPDIR=scratch)
    done = subprocess.run([sys.executable, "test/ris/heap_check.py"],
                          cwd=ROOT, env=env, capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


def main():
    header, blocks = split()
    workers = int(os.environ.get("RIS_CHECK_JOBS", os.cpu_count() or 1))
    with tempfile.TemporaryDirectory(prefix="ris-check-") as scratch:
        with concurrent.futures.ThreadPoolExecutor(workers) as pool:
            # Start the slowest gate first.
            heap_job = pool.submit(heap, scratch)
            jobs = [pool.submit(run, header, block, scratch, index)
                    for index, block in enumerate(blocks)]
            status = 0
            for job in jobs + [heap_job]:
                code, out = job.result()
                sys.stdout.write(out)
                sys.stdout.flush()
                status |= code != 0
    print("PASS: all ris checks" if status == 0 else "FAIL: ris checks")
    return status


if __name__ == "__main__":
    sys.exit(main())
