#!/usr/bin/env bash
# HTTP/2's frames past the 16 KiB first buffer grow a task-owned Conn's
# buffer inside a frame's tape block: two 1 MiB POSTs and a GET on one
# h2c connection (curl, prior knowledge) must arrive whole, on no heap.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
command -v curl >/dev/null || { echo skipped; exit 0; }
curl --version | grep -q nghttp2 || { echo skipped; exit 0; }
work=$(mktemp -d)
pid=
trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null; rm -rf "$work"' EXIT
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 "${RIS:-$root/bin/ris}" run \
  "$root/test/ris/http2_conn_growth.ri" -- "$port" >"$work/log" 2>&1 &
pid=$!
# `ris run` compiles first; under check.sh's parallel load that can take
# minutes, so wait for READY rather than a fixed time.
for _ in $(seq 3000); do grep -q READY "$work/log" && break; sleep 0.1; done
grep -q READY "$work/log" || { echo "server not ready:"; cat "$work/log"; exit 1; }
python3 -c 'import sys; sys.stdout.buffer.write(bytes(range(256))*4096)' \
  >"$work/a"
python3 -c 'import sys; sys.stdout.buffer.write(b"z"*1048573)' >"$work/b"
url="http://127.0.0.1:$port/"
out=$(curl -sS --http2-prior-knowledge --data-binary @"$work/a" "$url" \
  -w '\n' --next --http2-prior-knowledge --data-binary @"$work/b" "$url" \
  -w '\n' --next --http2-prior-knowledge "$url" -w '\n%{num_connects}\n')
# The program under `ris run` stops on TERM and reports its heap.
pkill -TERM -f "ris-run-http2_conn_growth-$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
pid=
want='HTTP/2 1048576 133693440
HTTP/2 1048573 127925906
HTTP/2 0 0
0'
# Before the reservation the grown buffers were program storage (53 KB).
taken=$(sed -n 's/^ris program storage: \([0-9]*\) .*/\1/p' "$work/log")
if [ "$out" = "$want" ] && [ -n "$taken" ] && [ "$taken" -lt 16384 ] &&
   grep -qx 'ris heap: 0 allocations, 0 bytes' "$work/log"; then
  echo "ok $taken"
else
  printf 'got:\n%s\nserver:\n%s\n' "$out" "$(cat "$work/log")"
  exit 1
fi
