#!/usr/bin/env bash
set -euo pipefail
RIS=${RIS:-./bin/ris}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
printf 'metadata\n' > "$work/file"
ln -s "$work/file" "$work/link"
"$RIS" build test/ris/file_metadata.ri -o "$work/gate"
for mode in ok size info nul; do
  code=0
  out=$(RIS_HEAP_STATS=1 "$work/gate" "$work/file" "$mode" \
    "$work/link" 2>&1) || code=$?
  grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"
  if [ "$mode" = ok ]; then
    [ "$code" -eq 0 ]
    grep -qxF 'PASS: file metadata, zero heap' <<<"$out"
  else
    [ "$code" -eq 1 ]
    if [ "$mode" = nul ]; then
      grep -qF 'path contains a NUL byte' <<<"$out"
    else
      grep -qxF "iyi: panic: File not found: $work/file.missing" <<<"$out"
    fi
  fi
done
