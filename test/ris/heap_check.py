#!/usr/bin/env python3
"""Fixed heap workloads, including one real request per server."""
import concurrent.futures
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
GATES = concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 1)


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
# the measured count plus slack; larger falls must lower it.
NETWORK_SLACK = 2


def compare(path, label, actual, budget, slack=0):
    if actual > budget:
        raise RuntimeError(f"{path}: {label} {actual} > budget {budget}")
    if actual < budget - slack:
        raise RuntimeError(f"{path}: {label} fell {budget} -> {actual}; "
                           "lower heap_budget.txt in this change")


def run_workload(binary, args, mode, *, stats=False):
    """Drive the same workload with either collector configuration."""
    env = os.environ.copy()
    env.pop("RIS_HEAP_STATS", None)
    if stats:
        env["RIS_HEAP_STATS"] = "1"
    env.pop("RIS_TAPE_STATS", None)
    response = b""
    if mode == "request":
        with subprocess.Popen([binary, *args], stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True,
                              env=env) as server:
            try:
                with selectors.DefaultSelector() as ready:
                    ready.register(server.stdout, selectors.EVENT_READ)
                    if not ready.select(30):
                        raise RuntimeError(
                            "web did not announce its listener")
                    line = server.stdout.readline()
                if not line:
                    stdout, stderr = server.communicate(timeout=30)
                    return subprocess.CompletedProcess(
                        server.args, server.returncode, stdout, stderr), b""
                port = measured(r"localhost:(\d+)/", line)
                address = ("127.0.0.1", port)
                socket_error = None
                try:
                    with socket.create_connection(address, 10) as sock:
                        sock.sendall(b"GET /users/1/status HTTP/1.1\r\n"
                                     b"Host: localhost\r\n"
                                     b"Connection: close\r\n\r\n")
                        while chunk := sock.recv(65536):
                            response += chunk
                except OSError as error:
                    # An allocation trap may close or reset the socket.
                    socket_error = error
                stdout, stderr = server.communicate(timeout=30)
                if socket_error and server.returncode == 0:
                    raise socket_error
                if (server.returncode == 0 and
                        b"<h1>alice</h1>" not in response):
                    server.kill()
                    raise RuntimeError(
                        f"bad web response: {response!r}")
                run = subprocess.CompletedProcess(
                    server.args, server.returncode,
                    re.sub(r"localhost:\d+/", "localhost:PORT/",
                           line + stdout), stderr)
            finally:
                if server.poll() is None:
                    server.kill()
                    server.communicate()
    else:
        run = subprocess.run([binary, *args], capture_output=True,
                             text=True, env=env, timeout=180)
    return run, response


def run_gate(source, binary, args, mode):
    built = command(["build", "--release", "--no-gc", "-o", binary,
                     source])
    if built.returncode:
        return built, b""
    return run_workload(binary, args, mode)


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

    def measure(index, path, scratch):
        """One sample: census, release build, run, budget, no-GC gate."""
        notes = []
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
        # The no-collector gate builds its own binary: start it now.
        gate = GATES.submit(run_gate, source,
                            str(Path(scratch) / f"gate-{index}"), args, mode)
        binary = str(Path(scratch) / f"sample-{index}")
        result = command(["build", "--release", "-o", binary, source])
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        run, response = run_workload(binary, args, mode, stats=True)
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
        # Every workload must succeed without a collector and preserve
        # stdout and the full HTTP response, even with network slack.
        gated, gated_response = gate.result()
        if (gated.returncode or gated.stdout != run.stdout or
                gated_response != response):
            raise RuntimeError(f"{path}: no-GC gate failed:\n"
                               f"{gated.stdout}{gated.stderr}")
        notes.append(f"heap     {path} {sites} {allocations} {mode}")
        budget = allocations + (NETWORK_SLACK if "request" in mode else 0)
        return f"{path} {sites} {budget} {mode}", notes

    rows = []
    with tempfile.TemporaryDirectory(prefix="ris-heap-") as scratch:
        # Samples are independent: build and run them on every core.
        workers = min(len(files), os.cpu_count() or 1)
        with concurrent.futures.ThreadPoolExecutor(workers) as pool:
            jobs = [pool.submit(measure, index, path, scratch)
                    for index, path in enumerate(files)]
            for job in jobs:
                row, notes = job.result()
                rows.append(row)
                for note in notes:
                    print(note, flush=True)
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
