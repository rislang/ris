#!/usr/bin/env python3
"""Exact fatal diagnostics under the allocation trap, in fresh processes."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
os.chdir(ROOT)
RIS = str(Path(os.environ.get("RIS", "./bin/ris")).resolve())
CASES = {
    "a": "iyi: tape size exceeds 2147483647: 2147483648",
    "b": "iyi: tape size overflow: 4611686018427387904 * 8",
    "c": "iyi: tape bad size: -1",
    "d": "iyi: tape bad size: -1",
    "e": "iyi: tape bad size: -1",
    "f": "iyi: tape bad size: -1",
    "g": "iyi: tape size exceeds 2147483647: 2147483648",
    "h": "iyi: tape size exceeds 2147483647: 4294967294",
    "i": "iyi: tape size overflow: 18446744073709551615 + 64",
    "j": "iyi: tape size overflow: 18446744073709551615 + 65535",
    "k": "iyi: tape size overflow: 18446744073709551615 + 7",
    "l": "iyi: tape size overflow: 18446744073709551608 + 16",
    "m": "iyi: a tape value made outside a tape block",
    "n": "iyi: mapping failed: 4611686018427453440 bytes",
    "o": "iyi: tape side reservation exhausted: 4611686018427387904",
    "p": "iyi: tape bad size: -9223372036854775808",
    "q": "iyi: tape array full: 2147483647",
    "r": "iyi: tape offset overflow: 2147483648",
    "s": "iyi: tape offset overflow: -2147483649",
    "t": "iyi: tape offset overflow: 2147483648",
    "u": "iyi: use growing_state before publishing tape bytes: 8",
}


def main():
    env = os.environ.copy()
    env.pop("RIS_HEAP_STATS", None)
    env.pop("RIS_TAPE_STATS", None)
    with tempfile.TemporaryDirectory(prefix="ris-size-") as scratch:
        binary = str(Path(scratch) / "failure")
        build = subprocess.run(
            [RIS, "build", "--release", "-o", binary,
             "test/ris/size_failure.ri"], capture_output=True, text=True,
            env=env, timeout=240)
        if build.returncode:
            raise RuntimeError(build.stdout + build.stderr)
        for mode, expected in CASES.items():
            run = subprocess.run([binary, mode], capture_output=True,
                                 text=True, env=env, timeout=10)
            if (run.returncode != 1 or run.stdout or
                    run.stderr != expected + "\n"):
                raise RuntimeError(f"{mode}: {run.returncode}, "
                                   f"{run.stdout!r}, {run.stderr!r}")
            print(f"fatal    size_failure ({mode})")


if __name__ == "__main__":
    main()
