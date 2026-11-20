#!/usr/bin/env bash
# Refuse the legacy String head path for requests in this gate's module
# copy: the wire case must exercise the tape path, even after refactoring.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src/std"
python3 - "$root/src/std/http.ri" "$work/src/std/http.ri" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
needle = '    at = head_end(limit, blank_first)\n'
assert source.count(needle) == 1, 'expected one legacy head reader'
source = source.replace(needle,
    '    raise "String-based request head" if what == "request"\n' + needle)
Path(sys.argv[2]).write_text(source)
PY
export RIS_PATH="$work/src:$root/src"
export RIS_CACHE_DIR="$work/cache"
out=$(RIS_TAPE_STATS=1 "${RIS:-$root/bin/ris}" run \
  "$root/test/ris/http_answer_split.ri" 2>&1) || {
  printf '%s\n' "$out" | tail -20
  exit 1
}
printf '%s\n' "$out" | grep -qx 'PASS: split slow head'
printf '%s\n' "$out" | grep -qF '0 growth moves'
printf '%s\n' "$out" | grep -qF '0 side regions'
echo 'PASS: split slow head, 0 growth moves, 0 side regions'
