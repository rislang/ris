#!/usr/bin/env bash
# The library's text building is linear. Runs
# test/cli/std_text_scale_exercise.ri - eight megabytes through join, reverse,
# tr, gsub, delete, squeeze, Regex#replace, each_line, String.build,
# Enumerable#join, String.join, CSV.build, HTTP.decode_chunked, center and a
# near-miss search, each checked - plain and optimised, under a clock sixty
# times what it needs, and proves the clock catches a builder that grows by a
# fixed step rather than doubling: every method above then copies what it has
# written on each write, which is the `result = result + piece` shape they all
# had, and the run does not end; and that it catches a join, a CSV build or a
# search that goes back to its quadratic shape on its own.
#
#     bash test/cli/std_text_scale_exercise.sh
#
# Needs `make` first. Exits non-zero if any step fails.

set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RIS="${RIS:-$REPO/bin/ris}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ris-exercise.XXXXXX")"
PSEP=":"
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT)
    REPO="$(cygpath -m "$REPO")"
    WORK="$(cygpath -m "$WORK")"
    PSEP=";"
    ;;
esac
trap 'rm -rf "$WORK"' EXIT

status=0
DONE="each checked"

run_case() {
  local label="$1" name="$2"
  shift 2
  if ! "$RIS" build "$@" -o "$WORK/$name" "$REPO/test/cli/std_text_scale_exercise.ri" >"$WORK/$name.build" 2>&1; then
    echo "  FAIL: $label: build failed"
    sed -n '1,12p' "$WORK/$name.build"
    status=1
    return
  fi
  "$WORK/$name" >"$WORK/$name.out" 2>&1
  local code=$?
  if [ "$code" -ne 0 ] || ! grep -q "$DONE" "$WORK/$name.out"; then
    echo "  FAIL: $label exited $code:"
    tail -3 "$WORK/$name.out" | sed 's/^/    /'
    status=1
    return
  fi
  echo "  ok   $label: $(cat "$WORK/$name.out")"
}

echo "== eight megabytes, plain and optimised"
run_case "default" plain
run_case "release" optimised --release

echo
if [ "$status" -eq 0 ]; then
  echo "text scale gate: every step held"
else
  echo "text scale gate: FAILED"
fi
exit "$status"
