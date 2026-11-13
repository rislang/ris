#!/usr/bin/env bash
# `ris test` walks only the project's own files (bug B1; the shared walk,
# doc/drafts/spec-blocks/spec-blocks.md 5.9, step 1).
#
#     bash test/cli/test_walk.sh
#
# A failing test under lib/ (another project's code), one under mods/ and
# one in a dot directory, and a passing one at the root: `ris test` with
# no path, and with `.`, must pass and run only the root one.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RIS="${RIS:-$REPO/bin/ris}"
case "$RIS" in /*) ;; *) RIS="$PWD/$RIS" ;; esac
mkdir -p "$REPO/test/cli/.work"
WORK="$(mktemp -d "$REPO/test/cli/.work/XXXXXX")"
cd "$WORK" || exit 1

fail='puts "ran a skipped test"
__iyi_exit(1)
'
mkdir -p lib/dep mods/dep .hidden
printf '%s' "$fail" > lib/dep/dep_test.ri
printf '%s' "$fail" > mods/dep/dep_test.ri
printf '%s' "$fail" > .hidden/hidden_test.ri
printf '__iyi_exit(0)\n' > root_test.ri

for args in "" "."; do
  echo "== ris test $args"
  # shellcheck disable=SC2086
  "$RIS" test --json $args > run.json 2>&1 ||
    { echo "FAIL: ris test $args failed:"; cat run.json; exit 1; }
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
files=[t["file"] for t in d["tests"]]
assert [f.split("/")[-1] for f in files]==["root_test.ri"], files
' run.json || { echo "FAIL: ran more than root_test.ri:"; cat run.json; exit 1; }
done

rm -rf "$WORK"
echo "test walk gate: lib/, mods/ and dot dirs skipped"
exit 0
