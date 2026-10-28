#!/usr/bin/env python3
"""Exercise listener ownership, limits, panic restart and cancellation."""
import concurrent.futures
import os
from pathlib import Path
import signal
import socket
import ssl
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
RIS = os.environ.get("RIS", str(ROOT / "bin/ris"))


def unused_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def request(peer, path="/hold", close=True):
    peer.sendall((f"GET {path} HTTP/1.1\r\nHost: localhost\r\n"
                  f"Connection: {'close' if close else 'keep-alive'}"
                  "\r\n\r\n").encode())
    data = b""
    while b"\r\n\r\n" not in data:
        part = peer.recv(1)
        if not part:
            raise EOFError("server closed before its response")
        data += part
    head = data.decode()
    assert head.startswith("HTTP/1.1 200 OK\r\n"), head
    length = int(next(line.split(":", 1)[1] for line in head.split("\r\n")
                      if line.lower().startswith("content-length:")))
    body = b""
    while len(body) < length:
        part = peer.recv(length - len(body))
        if not part:
            raise EOFError("short body")
        body += part
    return tuple(map(int, body.split()))


def exercise(binary):
    port, count = unused_port(), 3
    env = dict(os.environ, RIS_HEAP_STATS="1")
    process = subprocess.Popen([str(binary), str(port), str(count)],
                               stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, env=env)
    peers = []
    try:
        assert process.stdout.readline().strip() == "READY"

        def exchange(_):
            with socket.create_connection(("127.0.0.1", port), 8) as peer:
                return request(peer)

        with concurrent.futures.ThreadPoolExecutor(max_workers=36) as pool:
            replies = list(pool.map(exchange, range(36)))
        first = {worker for worker, calls, _, _ in replies if calls == 1}
        assert len(first) == count, ("configuration was shared", replies)
        events = [(start, 1) for _, _, start, _ in replies]
        events += [(end, -1) for _, _, _, end in replies]
        active = peak = 0
        for _, delta in sorted(events):
            active += delta
            peak = max(peak, active)
        assert peak == count, ("wrong concurrent connection bound", peak)
        print("PASS: simultaneous listeners, copied state, N connections")

        with socket.create_connection(("127.0.0.1", port), 8) as peer:
            first = request(peer, "/id", close=False)
            second = request(peer, "/id")
            assert first[0] == second[0] and second[1] == first[1] + 1
        print("PASS: keep-alive stays in its accepting task")

        with socket.create_connection(("127.0.0.1", port), 8) as peer:
            peer.sendall(b"GET /panic HTTP/1.1\r\nHost: h\r\n\r\n")
            try:
                assert peer.recv(1) == b""
            except ConnectionResetError:
                pass
        time.sleep(0.05)
        with concurrent.futures.ThreadPoolExecutor(max_workers=36) as pool:
            replies = list(pool.map(exchange, range(36)))
        assert len(replies) == 36
        assert any(calls == 1 for _, calls, _, _ in replies), replies
        print("PASS: handler panic closes its connection and worker restarts")

        with socket.create_connection(("127.0.0.1", port), 8) as peer:
            peer.sendall(b"GET /cancel HTTP/1.1\r\nHost: h\r\n\r\n")
            try:
                # Cancellation is cooperative: an already writable
                # response may finish before the worker's next wait.
                while peer.recv(4096):
                    pass
            except ConnectionResetError:
                pass
        time.sleep(0.05)
        with concurrent.futures.ThreadPoolExecutor(max_workers=36) as pool:
            replies = list(pool.map(exchange, range(36)))
        assert len(replies) == 36
        assert any(calls == 1 for _, calls, _, _ in replies), replies
        print("PASS: request cancellation closes and replaces its worker")

        # Leave reads parked both between requests and within a head.
        for index in range(12):
            peer = socket.create_connection(("127.0.0.1", port), 8)
            if index % 2:
                peer.sendall(b"GET / HTTP/1.1\r\n")
            peers.append(peer)
        process.send_signal(signal.SIGTERM)
        assert process.stdout.readline().strip() == "STOPPED"
        for peer in peers:
            peer.settimeout(0.2)
            try:
                assert peer.recv(1) == b""
            except ConnectionResetError:
                pass
        tail, errors = process.communicate(timeout=8)
        assert process.returncode == 0, (tail, errors)
        assert "ris heap: 0 allocations, 0 bytes" in errors, errors
        with socket.socket() as listener:
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("127.0.0.1", port))
            listener.listen()
        print("PASS: cancel closes clients and listeners; zero heap")
    except BaseException:
        if process.poll() is not None:
            print(process.stderr.read(), flush=True)
        raise
    finally:
        for peer in peers:
            peer.close()
        if process.poll() is None:
            process.kill()
            process.communicate()


def receive_exact(peer, size):
    data = b""
    while len(data) < size:
        part = peer.recv(size - len(data))
        if not part:
            raise EOFError("short HTTP/2 frame")
        data += part
    return data


def frame(kind, flags, stream, data=b""):
    return (len(data).to_bytes(3, "big") + bytes([kind, flags]) +
            stream.to_bytes(4, "big") + data)


def h2_request(peer, stream):
    # HPACK static GET, https; literal :path /id and :authority localhost.
    headers = bytes([0x82, 0x87, 0x04, 3]) + b"/id"
    headers += bytes([0x01, 9]) + b"localhost"
    peer.sendall(frame(1, 5, stream, headers))
    body = b""
    while True:
        head = receive_exact(peer, 9)
        size, kind, flags = int.from_bytes(head[:3], "big"), head[3], head[4]
        target = int.from_bytes(head[5:], "big") & 0x7fffffff
        data = receive_exact(peer, size)
        if kind == 4 and flags == 0:
            peer.sendall(frame(4, 1, 0))
        assert kind not in (3, 7), ("HTTP/2 refused", kind, data)
        if target == stream:
            if kind == 0:
                body += data
            if kind in (0, 1) and flags & 1:
                return tuple(map(int, body.split()))


def exercise_tls(binary, cert, key):
    port = unused_port()
    process = subprocess.Popen([str(binary), str(port), "2", str(cert),
                                str(key)], stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    peers = []
    try:
        assert process.stdout.readline().strip() == "READY"
        context = ssl.create_default_context(cafile=str(cert))
        context.set_alpn_protocols(["http/1.1"])
        for _ in range(6):
            with socket.create_connection(("127.0.0.1", port), 8) as raw:
                with context.wrap_socket(raw, server_hostname="localhost") as peer:
                    first = request(peer, "/id", close=False)
                    second = request(peer, "/id")
                    assert first[0] == second[0]
                    assert second[1] == first[1] + 1
                    assert peer.selected_alpn_protocol() == "http/1.1"
        print("PASS: TLS listeners and keep-alive use task-local TLS state")
        context.set_alpn_protocols(["h2"])
        with socket.create_connection(("127.0.0.1", port), 8) as raw:
            with context.wrap_socket(raw, server_hostname="localhost") as peer:
                assert peer.selected_alpn_protocol() == "h2"
                peer.sendall(b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" +
                             frame(4, 0, 0))
                first = h2_request(peer, 1)
                second = h2_request(peer, 3)
                assert first[0] == second[0] and second[1] == first[1] + 1
        print("PASS: HTTP/2 TLS requests stay on their accepting task")
        context.set_alpn_protocols(["http/1.1"])
        raw = socket.create_connection(("127.0.0.1", port), 8)
        idle = context.wrap_socket(raw, server_hostname="localhost")
        request(idle, "/id", close=False)
        peers.append(idle)
        # Neither an idle handshake nor a partial HTTP request delays stop.
        for _ in range(6):
            peers.append(socket.create_connection(("127.0.0.1", port), 8))
        process.send_signal(signal.SIGTERM)
        assert process.stdout.readline().strip() == "STOPPED"
        for peer in peers:
            peer.settimeout(0.2)
            try:
                assert peer.recv(1) == b""
            except ConnectionResetError:
                pass
        tail, errors = process.communicate(timeout=8)
        assert process.returncode == 0, (tail, errors)
        print("PASS: cancel closes pending TLS handshakes and listeners")
    except BaseException:
        if process.poll() is not None:
            print(process.stderr.read(), flush=True)
        raise
    finally:
        for peer in peers:
            peer.close()
        if process.poll() is None:
            process.kill()
            process.communicate()


def main():
    with tempfile.TemporaryDirectory(prefix="ris-http-prefork-") as work:
        binary = Path(work) / "server"
        build = subprocess.run([RIS, "build", "-o", str(binary),
                                str(ROOT / "test/ris/http_prefork.ri")],
                               capture_output=True, text=True, timeout=240)
        assert build.returncode == 0, build.stdout + build.stderr
        exercise(binary)
        # Setup failure must end the pool, with no listener fallback.
        with socket.socket() as occupied:
            occupied.bind(("127.0.0.1", 0))
            occupied.listen()
            port = occupied.getsockname()[1]
            failed = subprocess.run([str(binary), str(port), "3"],
                                    capture_output=True, text=True, timeout=8)
            assert failed.returncode != 0
            assert "SO_REUSEPORT listeners" in failed.stderr, failed.stderr
        failed = subprocess.run([str(binary), "0", "3"],
                                capture_output=True, text=True, timeout=8)
        assert failed.returncode != 0 and "choose a port" in failed.stderr
        failed = subprocess.run([str(binary), str(unused_port()), "0"],
                                capture_output=True, text=True, timeout=8)
        assert failed.returncode != 0 and "positive task count" in failed.stderr
        print("PASS: setup failure closes pool; zero port/task count refused")
        tls_binary = Path(work) / "tls-server"
        build = subprocess.run([RIS, "build", "-o", str(tls_binary),
                                str(ROOT / "test/ris/http_prefork_tls.ri")],
                               capture_output=True, text=True, timeout=240)
        assert build.returncode == 0, build.stdout + build.stderr
        cert, key = Path(work) / "cert.pem", Path(work) / "key.pem"
        generated = subprocess.run([
            "openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt",
            "ec_paramgen_curve:prime256v1", "-nodes", "-days", "1",
            "-subj", "/CN=localhost", "-keyout", str(key), "-out", str(cert),
        ], capture_output=True, text=True, timeout=15)
        assert generated.returncode == 0, generated.stderr
        exercise_tls(tls_binary, cert, key)


if __name__ == "__main__":
    main()
