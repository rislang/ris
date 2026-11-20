#!/usr/bin/env python3
"""Print fragmented TLS hello and WebSocket deflate-bomb response times."""
import os
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
RIS = os.environ.get("RIS", str(ROOT / "bin/ris"))


def port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def wait_port(number):
    for _ in range(300):
        try:
            with socket.create_connection(("127.0.0.1", number), timeout=1):
                return
        except OSError:
            time.sleep(0.05)
    raise RuntimeError("server did not listen")


def stop(process):
    process.terminate()
    process.wait(timeout=10)


def tls(work):
    key, cert = work / "key.pem", work / "cert.pem"
    subprocess.run([
        "openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt",
        "ec_paramgen_curve:P-256", "-nodes", "-keyout", str(key),
        "-out", str(cert), "-days", "1", "-subj", "/CN=localhost",
        "-addext", "subjectAltName=DNS:localhost",
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    number = port()
    server = subprocess.Popen([
        "openssl", "s_server", "-accept", str(number), "-cert", str(cert),
        "-key", str(key), "-www", "-quiet",
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_port(number)
        source_path = ROOT / "test/cli/std_tls_client.py"
        source = source_path.read_text()
        source = source.replace(
            '    elif name == "byte-records":\n',
            '    elif name == "byte-records":\n'
            '        hello_started = time.monotonic()\n')
        source = source.replace(
            '    sh = c.message()\n',
            '    sh = c.message()\n'
            '    if name == "byte-records":\n'
            '        print(f"TLS fragmented hello: '
            '{(time.monotonic() - hello_started) * 1000:.2f} ms", flush=True)\n', 1)
        namespace = {"__file__": str(source_path), "__name__": "timed_tls"}
        exec(compile(source, str(source_path), "exec"), namespace)
        root = namespace["x509"].load_pem_x509_certificate(cert.read_bytes())
        answer = namespace["run"]("byte-records", number, root)
        assert answer[0] == "held", answer
    finally:
        stop(server)


def websocket(work):
    binary = work / "server"
    subprocess.run([RIS, "build", "--release", "-o", str(binary),
                    str(ROOT / "test/speed/protocol_server.ri")], check=True)
    number = port()
    server = subprocess.Popen([str(binary), str(number), str(work / "ready")])
    try:
        wait_port(number)
        # Reuse the independent RFC 7692 peer from the functional gate.
        shell = (ROOT / "test/cli/std_websocket_exercise.sh").read_text()
        source = shell.split('<<\'PY\'\nimport base64, hashlib, os, random,',
                             1)[1]
        source = "import base64, hashlib, os, random," + source
        source = source.split('\nPY\n', 1)[0]
        prelude = source[:source.index('rng = random.Random(7692)')]
        namespace = {"__name__": "timed_websocket"}
        os.environ["PORT"] = str(number)
        exec(compile(prelude, "RFC 7692 peer", "exec"), namespace)
        compressor = namespace["compressor"]()
        bomb = b"".join(compressor.compress(bytes(1 << 20))
                        for _ in range(256))
        bomb += compressor.flush(namespace["zlib"].Z_SYNC_FLUSH)
        peer = namespace["Peer"]("permessage-deflate")
        started = time.monotonic()
        peer.fault(namespace["encode"](2, bomb[:-4], rsv=0x40), 1009,
                   "deflate bomb")
        print(f"WebSocket deflate bomb: "
              f"{(time.monotonic() - started) * 1000:.2f} ms", flush=True)
        assert not namespace["bad"], "peer refused incorrectly"
    finally:
        stop(server)


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="ris-protocol-timings-") as tmp:
        tls(Path(tmp))
        websocket(Path(tmp))
