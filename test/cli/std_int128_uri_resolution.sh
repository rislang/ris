#!/usr/bin/env bash
# Focused integer text and RFC 3986 section 5.4 gates.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RIS="${RIS:-$REPO/bin/ris}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export RIS_PATH="$REPO/src"
for mode in plain release; do
  flags=()
  if [ "$mode" = release ]; then flags=(--release); fi
  for name in int128 uri_resolution; do
    if ! "$RIS" build "${flags[@]}" \
        "$REPO/test/cli/std_${name}_exercise.ri" -o "$WORK/check" \
        >"$WORK/build.log" 2>&1; then
      tail -20 "$WORK/build.log"
      exit 1
    fi
    "$WORK/check"
    if [ "$name" = int128 ]; then
      for failure in signed-base unsigned-base parse-base \
                     signed-range unsigned-range; do
        if "$WORK/check" "$failure" >"$WORK/failure.log" 2>&1; then
          echo "expected refusal: $failure"
          exit 1
        fi
        if ! grep -Eq 'base out of range|not a 128-bit number' \
            "$WORK/failure.log"; then
          tail -8 "$WORK/failure.log"
          exit 1
        fi
      done
    fi
  done
done
echo '128-bit text and URI resolution checks passed'
