#!/usr/bin/env python3
"""Fixed heap workloads, including one real request per server."""
import os
from pathlib import Path
import re
import selectors
import socket
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
os.chdir(ROOT)
RIS = str(Path(os.environ.get("RIS", "./bin/ris")).resolve())
TABLE = ROOT / "test/ris/heap_budget.txt"
RECORD = "--record" in sys.argv


def command(args, *, stats=False):
    env = os.environ.copy()
    env.pop("RIS_HEAP_STATS", None)
    env.pop("RIS_TAPE_STATS", None)
    if stats:
        env["RIS_HEAP_STATS"] = "1"
    return subprocess.run([RIS, *args], capture_output=True, text=True,
                          env=env, timeout=240)


def measured(pattern, text):
    match = re.search(pattern, text, re.M)
    if not match:
        raise RuntimeError(f"missing heap count:\n{text}")
    return int(match[1])


# Socket workloads vary by a few allocations with timing: their budget is
# the observed maximum, and only a fall past this slack must lower it.
NETWORK_SLACK = 4


def compare(path, label, actual, budget, slack=0):
    if actual > budget:
        raise RuntimeError(f"{path}: {label} {actual} > budget {budget}")
    if actual < budget - slack:
        raise RuntimeError(f"{path}: {label} fell {budget} -> {actual}; "
                           "lower heap_budget.txt in this change")


def main():
    budgets = {}
    if not RECORD:
        for line in TABLE.read_text().splitlines():
            if line and not line.startswith("#"):
                path, sites, allocations, mode = line.split()
                budgets[path] = (int(sites), int(allocations), mode)
    files = sorted(str(p) for p in Path("samples/ris").rglob("*.ri"))
    if not RECORD and set(files) != set(budgets):
        raise RuntimeError("sample list differs from heap_budget.txt")
    rows = []
    with tempfile.TemporaryDirectory(prefix="ris-heap-") as scratch:
        for index, path in enumerate(files):
            result = command(["heap", "--user", path])
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
            sites = measured(r"^total: (\d+)$", result.stdout)
            source = path
            name = Path(path).stem
            mode = {"escape": "tape", "query": "tape",
                    "serve": "answer-request", "web": "request"}.get(
                        name, "default")
            args = ["tape"] if mode == "tape" else []
            if mode == "answer-request":
                # Keep serve's loopback client and validate one full answer.
                text = Path(path).read_text()
                text = text.replace("N = 200000", "N = 1")
                text = text.replace("REQUEST * 1000", "REQUEST")
                text = text.replace("(N // 1000).times", "N.times")
                source = str(Path(scratch) / f"{name}.ri")
                Path(source).write_text(text)
                args = ["answer"]
            if mode == "request":
                text = Path(path).read_text()
                # Stop accepting; the active handler still writes its response.
                text = text.replace("Server.answer(listener) do |req, res|",
                    "Server.answer(listener) do |req, res|\n"
                    "  listener.close")
                source = str(Path(scratch) / f"{name}.ri")
                Path(source).write_text(text)
                args = ["0"]
            binary = str(Path(scratch) / f"sample-{index}")
            result = command(["build", "--release", "-o", binary, source])
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
            env = dict(os.environ, RIS_HEAP_STATS="1")
            env.pop("RIS_TAPE_STATS", None)
            if mode == "request":
                with subprocess.Popen([binary, *args], stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, text=True,
                                      env=env) as server:
                    try:
                        ready = selectors.DefaultSelector()
                        ready.register(server.stdout, selectors.EVENT_READ)
                        if not ready.select(30):
                            server.kill()
                            raise RuntimeError(
                                "web did not announce its listener")
                        line = server.stdout.readline()
                        ready.close()
                        port = measured(r"localhost:(\d+)/", line)
                        address = ("127.0.0.1", port)
                        with socket.create_connection(address, 10) as sock:
                            sock.sendall(b"GET /users/1/status HTTP/1.1\r\n"
                                         b"Host: localhost\r\n"
                                         b"Connection: close\r\n\r\n")
                            response = b""
                            while chunk := sock.recv(65536):
                                response += chunk
                        if b"<h1>alice</h1>" not in response:
                            server.kill()
                            raise RuntimeError(
                                f"bad web response: {response!r}")
                        stdout, stderr = server.communicate(timeout=30)
                        run = subprocess.CompletedProcess(
                            server.args, server.returncode,
                            line + stdout, stderr)
                    finally:
                        if server.poll() is None:
                            server.kill()
                            server.communicate()
            else:
                run = subprocess.run([binary, *args], capture_output=True,
                                     text=True, env=env, timeout=180)
            if run.returncode:
                raise RuntimeError(f"{path}: {run.stdout}{run.stderr}")
            allocations = measured(r"^ris heap: (\d+) allocations,",
                                   run.stderr)
            if not RECORD:
                old_sites, old_allocations, old_mode = budgets[path]
                if mode != old_mode:
                    raise RuntimeError(f"{path}: workload changed")
                compare(path, "static sites", sites, old_sites)
                compare(path, "allocations", allocations, old_allocations,
                        NETWORK_SLACK if "request" in mode else 0)
            # Every workload also runs behind the no-collector gate. A
            # positive count must trap, a zero count must preserve output.
            gated = command(["run", "--release", "--no-gc", source,
                             "--", *args])
            gc_refusal = ("std/gc speaks for iyi's own collector" in
                          gated.stderr + gated.stdout)
            if gc_refusal and gated.returncode:
                print(f"gate     {path}: std/gc requires a collector")
            elif allocations:
                if not gated.returncode or (
                        "ris: heap allocation with --no-gc:" not in
                        gated.stderr + gated.stdout):
                    raise RuntimeError(f"{path}: missing trap:\n"
                                       f"{gated.stdout}{gated.stderr}")
            elif gated.returncode or gated.stdout != run.stdout:
                raise RuntimeError(f"{path}: zero-heap gate failed:\n"
                                   f"{gated.stdout}{gated.stderr}")
            rows.append(f"{path} {sites} {allocations} {mode}")
            print(f"heap     {rows[-1]}", flush=True)
    if RECORD:
        TABLE.write_text(
            "# sample  static-user-sites  runtime-allocations  workload\n"
            "# release builds; no stdin; default args unless named below.\n"
            "# tape: argv=tape; answer-request: serve argv=answer, "
            "one request.\n"
            "# request: web argv=0, one HTTP GET.\n"
            + "\n".join(rows) + "\n")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as error:
        print(f"FAILED   heap: {error}", file=sys.stderr)
        sys.exit(1)
