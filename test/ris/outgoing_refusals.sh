#!/usr/bin/env bash
# Outgoing's refusals are raised when the program runs, so each case is a
# program run with `ris run`: it must fail with its message and never
# reach the line after the call. `expect` in check.sh only builds.
set -uo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
RIS=${RIS:-$root/bin/ris}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failed=0

# refused NAME NEEDLE: run $work/NAME.ri, read from stdin.
refused() {
  local name=$1 needle=$2 out code
  cat > "$work/$name.ri"
  out=$("$RIS" run "$work/$name.ri" 2>&1); code=$?
  if [ "$code" -eq 0 ] || ! grep -qF -- "$needle" <<<"$out" ||
      grep -qF 'reached' <<<"$out"; then
    echo "FAILED   outgoing $name: $out"; failed=1
  fi
}

refused length_body 'HTTP: length= 9 with a body of 3 bytes' <<'RI'
import std/http::{Outgoing, Server}
res = Outgoing.new
res.body << "abc"
res.length = 9_i64
puts Server.format_response(res, false, false)
puts "reached"
RI

refused length_negative 'HTTP: not a length: -1' <<'RI'
import std/http::{Outgoing}
res = Outgoing.new
res.length = -1_i64
puts "reached"
RI

refused header_nested 'HTTP: a header inside a header block' <<'RI'
import std/http::{Outgoing}
res = Outgoing.new
res.header("A") { |w| w << "x"; res.header("B", "y") }
puts "reached"
RI

refused header_break 'HTTP: header B contains a line break' <<'RI'
import std/http::{Outgoing}
res = Outgoing.new
res.header("B") { |w| w << "a\r\nInjected: 1"; nil }
puts "reached"
RI

[ "$failed" -eq 0 ] && echo 'PASS: length= and block headers refused'
exit "$failed"
