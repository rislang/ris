#!/usr/bin/env bash
# Run by hand on a quiet machine; reports times without pass/fail budgets.
set -eu
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ris-collections-speed.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
"${RIS:-$REPO/bin/ris}" build --release -o "$WORK/run" \
  "$REPO/test/speed/collections.ri"
"$WORK/run"
