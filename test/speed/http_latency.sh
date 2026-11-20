#!/usr/bin/env bash
# Print loopback medians. Timing values never determine success.
set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RIS="${RIS:-$REPO/bin/ris}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ris-http-latency.XXXXXX")"
SERVER=""
trap '[ -z "$SERVER" ] || kill "$SERVER" 2>/dev/null || true; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tls"
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout "$WORK/tls/root.key" -out "$WORK/tls/root.pem" -days 1 \
  -subj /CN=ris-speed-root >/dev/null 2>&1
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout "$WORK/tls/leaf.key" -out "$WORK/tls/leaf.csr" \
  -subj /CN=localhost >/dev/null 2>&1
cat >"$WORK/tls/leaf.ext" <<'EXT'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost
EXT
openssl x509 -req -in "$WORK/tls/leaf.csr" -CA "$WORK/tls/root.pem" \
  -CAkey "$WORK/tls/root.key" -CAcreateserial -days 1 \
  -extfile "$WORK/tls/leaf.ext" -out "$WORK/tls/p256.pem" \
  >/dev/null 2>&1
PY="$(command -v python3)"
LATENCY_SELF="plain http://, std/http at both ends, a GET on a new connection
plain http://, a kept connection, an answer the server streams
https://, std/http at both ends, a GET on a new connection
https://, a kept connection, an answer the server streams
https://, Nagle on at the client, its handshake and a GET"
LATENCY_SSERVER="https:// to s_server, a GET on a new connection
https:// to s_server, Nagle on at the client, its handshake and a GET"
LATENCY_CURL="curl to std/http's https:// server, a GET on a new connection"
LATENCY_ALONE="no ChangeCipherSpec written alone, at either end, as strace saw the writes"
latency_openssl=yes
latency_curl=yes
latency_strace=no
# Whether a stall shows in time here: Linux's loopback delays an ACK 40 ms
# at least, which is the stall these checks time; darwin's showed none -
# every check held on the CI runner with Nagle left on, and with the
# client's flight in two writes (job 119078193573) - and Windows' is not
# known to. Elsewhere a broken copy timing does not catch is said to be
# unmeasured there, never caught, and the Nagle copy is held by the
# TCP_NODELAY check, which reads the option on every platform.
latency_timing=no
case "$(uname -s)" in
  Linux) latency_timing=yes ;;
esac
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT) latency_openssl=no; latency_curl=no ;;
  Linux) command -v strace >/dev/null 2>&1 && strace -f -qq -e trace=write -o /dev/null true >/dev/null 2>&1 && latency_strace=yes ;;
esac
LATENCY_OPENSSL=openssl
for candidate in /opt/homebrew/opt/openssl@3/bin/openssl /usr/local/opt/openssl@3/bin/openssl; do
  if [ -x "$candidate" ]; then
    LATENCY_OPENSSL="$candidate"
    break
  fi
done
if [ -z "$PY" ] || ! command -v "$LATENCY_OPENSSL" >/dev/null 2>&1 || ! "$LATENCY_OPENSSL" version 2>/dev/null | grep -q '^OpenSSL '; then
  latency_openssl=no
fi
command -v curl >/dev/null 2>&1 || latency_curl=no
# latency_run <binary>: every line the binary and its peers answer.
latency_run() {
  local bin="$1" port pid
  timeout 120 "$bin" self "$WORK/tls/p256.pem" "$WORK/tls/leaf.key" "$WORK/tls/root.pem" 50 2>&1
  if [ "$latency_openssl" = yes ]; then
    port="$("$PY" -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
    "$LATENCY_OPENSSL" s_server -accept "127.0.0.1:$port" -www -tls1_3 -cert "$WORK/tls/p256.pem" -key "$WORK/tls/leaf.key" \
      >"$WORK/latency-s_server.log" 2>&1 </dev/null &
    pid=$!
    SERVER="$pid"
    for _ in $(seq 1 50); do
      "$PY" -c "import socket; socket.create_connection(('127.0.0.1', $port), 1).close()" 2>/dev/null && break
      sleep 0.1
    done
    timeout 120 "$bin" s_server "$port" "$WORK/tls/root.pem" 50 2>&1
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    SERVER=""
  fi
  if [ "$latency_curl" = yes ]; then
    rm -f "$WORK/latency.port"
    "$bin" serve "$WORK/latency.port" "$WORK/tls/p256.pem" "$WORK/tls/leaf.key" >/dev/null 2>&1 &
    pid=$!
    SERVER="$pid"
    for _ in $(seq 1 100); do
      [ -s "$WORK/latency.port" ] && break
      sleep 0.1
    done
    port="$(cat "$WORK/latency.port" 2>/dev/null)"
    # A curl that could not speak to the server answers 000 in no time,
    # which is no latency: only 200s are counted, and all 50 must be.
    for _ in $(seq 1 51); do
      curl -s -o /dev/null -w '%{http_code} %{time_total}\n' --max-time 10 --cacert "$WORK/tls/root.pem" "https://localhost:$port/"
    done | tail -50 | awk '$1 == "200" { print $2 }' | sort -n | awk -v label="$LATENCY_CURL" '{ t[NR] = $1 * 1000 } END {
      m = NR > 0 ? t[int(NR / 2) + 1] : 0
      if (NR != 50) printf "%s: %d of 50 answered 200\n", label, NR
      else printf "%s: median %.2f ms of %d\n", label, m, NR }'
    curl -s -o /dev/null --max-time 10 --cacert "$WORK/tls/root.pem" "https://localhost:$port/quit"
    wait "$pid" 2>/dev/null || true
    SERVER=""
  fi
  if [ "$latency_strace" = yes ]; then
    strace -f -qq -e trace=sendto,write -o "$WORK/latency.trace" timeout 60 "$bin" once "$WORK/tls/p256.pem" "$WORK/tls/leaf.key" "$WORK/tls/root.pem" >/dev/null 2>&1
    echo "$LATENCY_ALONE: $(grep -c '"\\24\\3\\3\\0\\1\\1", 6' "$WORK/latency.trace")"
  fi
}
"$RIS" build --release -o "$WORK/latency" \
  "$REPO/test/speed/http_latency.ri"
"$WORK/latency"
latency_run "$WORK/latency"
