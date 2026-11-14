#!/usr/bin/env bash
# A copy of std under an RIS_PATH entry's std/ (as the test/cli mutation
# scripts make it) is lowered as std is: its `s = ""` text grows in place.
set -uo pipefail
cd "$(dirname "$0")/../.."
RIS=${RIS:-./bin/ris}
mkdir -p tmp
work=$(mktemp -d tmp/patched_std.XXXXXX)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/patched/std"
cp src/std/tar.ri "$work/patched/std/tar.ri"
if out=$(RIS_PATH="$work/patched:$PWD/src:$PWD/samples/ris" \
    "$RIS" build --no-codegen test/cli/std_tar_exercise.ri 2>&1); then
  echo "builds   patched std/tar.ri"
else
  echo "FAILED   patched std/tar.ri: $(tail -5 <<<"$out")"; exit 1
fi
