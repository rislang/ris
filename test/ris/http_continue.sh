#!/usr/bin/env bash
# Export an internal connection only in this gate's module copy: the test
# can preload its buffer without relying on TCP read boundaries.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src/std"
python3 - "$root/src/std/http.iyi" "$work/src/std/http.iyi" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
old = "\nstruct Conn\n"
assert source.count(old) == 1, "expected one internal Conn declaration"
Path(sys.argv[2]).write_text(source.replace(old, "\npub struct Conn\n"))
PY
export IYI_PATH="$work/src:$root/src"
export IYI_CACHE_DIR="$work/cache"
"${RIS:-$root/bin/ris}" run "$root/test/ris/http_continue.ri"
