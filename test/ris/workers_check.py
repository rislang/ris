#!/usr/bin/env python3
"""Check the teaching sample and its bounded refusal paths."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RIS = str((ROOT / os.environ.get("RIS", "./bin/ris")).resolve())
SOURCE = ROOT / "samples/iyi/workers.iyi"
EXPECTED = '91\n{"<one>", "<two>"}\nslow timed out\n'


def run_sample(source, binary):
    built = subprocess.run(
        [RIS, "build", str(source), "-o", str(binary)],
        cwd=ROOT, capture_output=True, text=True)
    if built.returncode:
        raise RuntimeError(built.stdout + built.stderr)
    return subprocess.run([str(binary)], cwd=ROOT, capture_output=True,
                          text=True, timeout=15)


def main():
    original = SOURCE.read_text()
    with tempfile.TemporaryDirectory(prefix="ris-workers-") as scratch:
        scratch = Path(scratch)
        normal = run_sample(SOURCE, scratch / "workers")
        assert normal.returncode == 0, normal.stdout + normal.stderr
        assert normal.stdout == EXPECTED, repr(normal.stdout)
        print("runs     workers (expected pool and typed-pair results)")
        # Group join plus empty queues proves all nine Jobs were consumed:
        # six work variants and exactly one quit per worker, with no extras.
        drained = original + '''
raise "leftover Job" unless RisBoard.poll(Job) == {nil, false}
raise "leftover Result" unless RisBoard.poll(Result) == {nil, false}
'''
        variants = [
            ("join", drained, None),
            ("work_refusal", original.replace("Job, 9_i64", "Job, 1_i64"),
             "job queue full; job was not published"),
            ("quit_refusal", original.replace("Job, 9_i64", "Job, 6_i64"),
             "job queue full; quit was not published"),
            ("result_refusal",
             original.replace("Result, 6_i64", "Result, 1_i64"),
             "result queue full; result was not published"),
        ]
        for name, text, error in variants:
            source = scratch / (name + ".iyi")
            source.write_text(text)
            done = run_sample(source, scratch / name)
            output = done.stdout + done.stderr
            if error is None:
                assert done.returncode == 0, output
                assert done.stdout == EXPECTED, repr(done.stdout)
                print("runs     workers_join (quits consumed, queues empty)")
            else:
                assert done.returncode != 0 and error in output, output
                print(f"refused  workers_{name} (fails without spinning)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
