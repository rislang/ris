#!/usr/bin/env bash
# A `.iyi/` build cache, or any directory whose name ends in .iyi, is not a
# source file: `ris check` walks past it. A regular `x.iyi` file is still
# refused by name (SPEC 6.10). After the .ri rename, `ris check` refused
# `./.iyi` (an old cache holding .o files) as "a ris file ends in .ri".
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RIS=${RIS:-$ROOT/bin/ris}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

cd "$WORK"
printf 'puts "hi"\n' > main.ri
mkdir -p .iyi foo.iyi
printf 'obj' > .iyi/main.o
printf 'obj' > foo.iyi/a.o

for verb in check; do
  out=$("$RIS" $verb 2>&1)
  if grep -q 'ends in .ri' <<<"$out"; then
    fail "ris $verb refused a directory: $out"
  fi
done

printf 'puts "hi"\n' > x.iyi
out=$("$RIS" check 2>&1) && fail "ris check accepted x.iyi: $out"
grep -q 'x.iyi: a ris file ends in .ri' <<<"$out" ||
  fail "ris check: wrong refusal for x.iyi: $out"
echo "iyi_cache_dir: ok"
