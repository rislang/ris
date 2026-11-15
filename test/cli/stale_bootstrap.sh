#!/usr/bin/env bash
#
# The compiler's own build rules must not pick up a built compiler.
#
# `bin/crystal` runs `.build/crystal` whenever it exists. A compiler built
# from this source has String as a struct, and the compiler's source uses
# the Crystal prelude, where String is a class, so `make ris` after any
# earlier `make crystal`, `make test` or `make` failed with "String is not
# a class, it's a struct". Each rule that builds a compiler passes
# CRYSTAL_SKIP_BUILT=1, so the parent (bootstrap) Crystal builds it.
#
# This runs the real commands from `make -n` with the real `bin/crystal` in a
# scratch root, where `.build/crystal` is a stale compiler that fails and the
# parent `crystal` is a stand-in that succeeds. Remove CRYSTAL_SKIP_BUILT
# from any of those rules and it fails.
#
#   bash test/cli/stale_bootstrap.sh
#
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

mkdir -p "$scratch/bin" "$scratch/.build" "$scratch/parent"
cp "$root/bin/crystal" "$scratch/bin/crystal"
printf '#!/bin/sh\necho "stale .build/crystal ran" >&2\nexit 1\n' \
  > "$scratch/.build/crystal"
printf '#!/bin/sh\nexit 0\n' > "$scratch/parent/crystal"
chmod +x "$scratch/bin/crystal" "$scratch/.build/crystal" \
  "$scratch/parent/crystal"

targets=(ris crystal crystal-front crystal-daemon ris-daemon)
# Join continued lines, keep each command that builds a compiler source.
mapfile -t commands < <(
  make -C "$root" -s -n -B "${targets[@]}" 2>/dev/null |
    sed -e ':a' -e '/\\$/N; s/\\\n//; ta' |
    grep -E 'bin/crystal build .* src/compiler/[a-z_]+\.cr'
)

if [ "${#commands[@]}" -lt "${#targets[@]}" ]; then
  echo "FAIL: found ${#commands[@]} compiler build commands," \
    "expected ${#targets[@]}" >&2
  exit 1
fi

fail=0
for cmd in "${commands[@]}"; do
  if ! (cd "$scratch" && CRYSTAL="$scratch/parent/crystal" \
    bash -c "$cmd" >/dev/null 2>"$scratch/err"); then
    echo "FAIL: used the built compiler: ${cmd##*-o }" >&2
    sed 's/^/  /' "$scratch/err" >&2
    fail=1
  fi
done
[ "$fail" = 0 ] && echo "ok: ${#commands[@]} compiler builds use the bootstrap"
exit "$fail"
