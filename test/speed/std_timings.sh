#!/usr/bin/env bash
# Former CLI timing budgets: print costs without pass/fail thresholds.
set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ris-std-timings.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
for name in base64 static_array uuid time indexable compress yaml \
            text_scale slice regex poller http_upload; do
  echo "== $name"
  "${RIS:-$REPO/bin/ris}" build --release -o "$WORK/run" \
    "$REPO/test/speed/$name.ri"
  "$WORK/run"
done
