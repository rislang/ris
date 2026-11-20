#!/usr/bin/env bash
# Parallel CPU throughput, measured by hand on a quiet machine.
# No timing is a pass/fail gate (AGENTS.md).
set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RIS="${RIS:-$REPO/bin/ris}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ris-parallel-speed.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
"$RIS" build --release "$REPO/test/cli/parallel_exercise.ri" -o exercise
for workers in 1 2 4 8; do
  for run in 1 2 3; do
    ./exercise speed "$workers" 16 40000000
  done
done
