#!/usr/bin/env bash
# Every invocation below starts with fresh process-wide mail and limits.
set -uo pipefail
cd "$(dirname "$0")/../.."
RIS=${RIS:-./bin/ris}
status=0
for gate in core copies waits parallel survival modules limits; do
  for mode in gc no-gc; do
    flags=()
    [ "$mode" = gc ] || flags+=(--no-gc)
    out=$(RIS_HEAP_STATS=1 "$RIS" run "${flags[@]}" \
      "test/ris/board_$gate.ri" 2>&1)
    code=$?
    if [ "$mode" = gc ]; then
      witness=$(sed -n 's/^ris heap: /heap /p' <<<"$out")
      heap_ok=0
      [ -z "$witness" ] || heap_ok=1
    else
      witness='zero heap'
      heap_ok=0
      grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out" && heap_ok=1
    fi
    if [ "$code" -eq 0 ] && [ "$heap_ok" -eq 1 ] &&
        grep -q '^PASS: board ' <<<"$out"; then
      echo "runs     board_$gate ($mode, $witness)"
    else
      echo "FAILED   board_$gate ($mode): $out"; status=1
    fi
  done
done
out=$("$RIS" run test/ris/board_gc.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'PASS: board GC' ]; then
  echo 'runs     board_gc (parallel collection, parked takers, packed mail)'
else
  echo "FAILED   board_gc: $out"; status=1
fi
for fault in panic cancel; do
  flags=()
  [ "$fault" = panic ] || flags+=(--no-gc)
  out=$("$RIS" run "${flags[@]}" -D "ris_board_test_$fault" \
    test/ris/board_copy_failure.ri 2>&1)
  if [ "$?" -eq 0 ] &&
      grep -qxF 'PASS: board copy rollback' <<<"$out"; then
    echo "runs     board_copy_failure ($fault, claim and tape rollback)"
  else
    echo "FAILED   board_copy_failure ($fault): $out"; status=1
  fi
done
for bound in bytes count; do
  if [ "$bound" = bytes ]; then
    needle='ris: board image exceeds 16777216 bytes:'
  else
    needle='ris: board count exceeds 1048576:'
  fi
  out=$("$RIS" run --no-gc "test/ris/board_bounds_$bound.ri" 2>&1)
  if [ "$?" -ne 0 ] && grep -qF "$needle" <<<"$out"; then
    echo "refused  board_bounds_$bound (physical bound, fresh process)"
  else
    echo "FAILED   board_bounds_$bound: $out"; status=1
  fi
done
out=$("$RIS" run --no-gc test/ris/board_bad_limit.ri 2>&1)
if [ "$?" -ne 0 ] &&
    grep -qF 'ris: board limit must be positive:' <<<"$out"; then
  echo 'refused  board_bad_limit (nonpositive count)'
else
  echo "FAILED   board_bad_limit: $out"; status=1
fi
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
out=$("$RIS" build --no-gc -o "$scratch/board" \
  test/ris/board_parallel.ri 2>&1)
if [ "$?" -eq 0 ]; then
  symbols=$(nm -u "$scratch/board" 2>&1)
  if [ "$?" -eq 0 ] && ! grep -Eq \
      '(^|[[:space:]])(malloc|calloc|realloc|free|GC_[a-zA-Z_]+)(@|$)' \
      <<<"$symbols"; then
    echo 'runs     board no-GC link audit (no general allocator imports)'
  else
    echo "FAILED   board link audit: $symbols"; status=1
  fi
else
  echo "FAILED   board audit build: $out"; status=1
fi
exit "$status"
