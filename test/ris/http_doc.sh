#!/bin/sh
# Documentation exports the complete HTTP import graph. Refusal-only APIs
# must keep their diagnostics without failing that export.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ris=${RIS:-$root/bin/ris}
export IYI_CACHE_DIR="$work/cache"
"$ris" doc std/http > "$work/doc"
grep -F 'pub struct HTTP' "$work/doc" > /dev/null
grep -F 'pub struct Server' "$work/doc" > /dev/null
"$ris" run "$root/test/ris/http_head_legacy.ri"
refused() {
  sentence=$1
  if "$ris" build --no-codegen "$work/case.ri" > "$work/log" 2>&1; then
    echo "FAILED: expected refusal: $sentence"
    exit 1
  fi
  grep -F "$sentence" "$work/log" > /dev/null
}
cat > "$work/case.ri" <<'EOF'
module http_doc_case
import std/http::{Server}
Server.parse_head("")
EOF
refused 'Server.parse_head(text) is gone'
cat > "$work/case.ri" <<'EOF'
module http_doc_case
import std/http::{Server}
Server.parse_head("", 0, true)
EOF
refused 'Server.parse_head(bytes, from, complete) takes the fields'
cat > "$work/case.ri" <<'EOF'
module http_doc_case
import std/http::{HTTP}
HTTP.upgrade("http://localhost/", "echo")
EOF
refused 'HTTP.upgrade returns no owner'
cat > "$work/case.ri" <<'EOF'
module http_doc_case
import std/tls::{TlsClient}
TlsClient.over(0, host: "localhost")
EOF
refused 'TlsClient.over returns no owner'
cat > "$work/case.ri" <<'EOF'
module http_doc_case
import std/tls::{TlsServer}
TlsServer.over(0, 0)
EOF
refused 'TlsServer.over is gone'
cat > "$work/case.ri" <<'EOF'
module http_doc_case
import std/x509::{Certificate}
Certificate.from_pem("")
EOF
refused 'Certificate.from_pem returns no owner'
echo 'HTTP documentation: ok'
