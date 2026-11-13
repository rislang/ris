#!/usr/bin/env bash
# spec: 6.10@9b9f5766
# A ris file ends in .ri; iyi's names are refused or not read
# (doc/drafts/ri-extension/DRAFT.md, 7.1-7.5).
#
#     bash test/cli/ri_only.sh
#
# Runs the real compiler on scratch projects: every boundary of 7.5's
# table, 7.3's rows for RIS_PATH and RIS_CACHE_DIR and `ris env`, 7.2's
# switches and artifacts, 7.1's printed text, and the repository holds no
# tracked .iyi file outside doc/archive and doc/reference.

set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RIS="${RIS:-$REPO/bin/ris}"
case "$RIS" in /*) ;; *) RIS="$REPO/${RIS#./}" ;; esac
mkdir -p "$REPO/test/cli/.work"
WORK="$(mktemp -d "$REPO/test/cli/.work/XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# Every IYI_ and RIS_ variable is the case's own.
for v in $(env | sed -n 's/^\(\(IYI\|RIS\)_[A-Z_]*\)=.*/\1/p'); do
  unset "$v"
done
export RIS_CACHE_DIR="$WORK/cache"
status=0

say() {
  if [ "$2" -eq 0 ]; then
    echo "  ok   $1"
  else
    echo "  FAIL $1"
    status=1
  fi
}

# refused NAME OUT TEXT: the command exited 1 and OUT holds TEXT.
refused() {
  say "$1" "$([ "$rc" -eq 1 ] && grep -qF -- "$3" "$2"; echo $?)"
}

fresh() {
  rm -rf "$WORK/p" && mkdir -p "$WORK/p" && cd "$WORK/p" || exit 1
}

hello='module main

puts "hi"
'
rename='a ris file ends in .ri; rename it to'

echo "7.5: where a .iyi file is refused"
for verb in run build check test doc; do
  fresh
  printf '%s' "$hello" > main.iyi
  "$RIS" $verb main.iyi > out.txt 2>&1; rc=$?
  refused "ris $verb main.iyi" out.txt "main.iyi: $rename main.ri"
done

fresh
printf '%s' "$hello" > main.ri
printf 'module main_test\n\nassert_eq 1, 1\n' > main_test.ri
printf '%s' "$hello" > old.iyi
"$RIS" test . > out.txt 2>&1; rc=$?
refused "the project walk (ris test .) refuses old.iyi" out.txt \
  "old.iyi: $rename old.ri"
"$RIS" check > out.txt 2>&1; rc=$?
refused "check's own walk refuses old.iyi" out.txt "old.iyi: $rename old.ri"

fresh
printf 'module main\n\nimport lib::*\n\nputs lib_value\n' > main.ri
printf 'module lib\n\npub def lib_value : Int32\n  7\nend\n' > lib.iyi
"$RIS" run main.ri > out.txt 2>&1; rc=$?
refused "an import only lib.iyi satisfies is refused, naming it" out.txt \
  "lib.iyi: $rename lib.ri"
cp lib.iyi lib.ri
"$RIS" run main.ri > out.txt 2>&1; rc=$?
say "both lib.ri and lib.iyi: the import uses lib.ri" \
  "$([ "$rc" -eq 0 ] && grep -qx 7 out.txt; echo $?)"
printf 'module main_test\n\nassert_eq 1, 1\n' > main_test.ri
"$RIS" test . > out.txt 2>&1; rc=$?
refused "both present: the walk still refuses lib.iyi" out.txt \
  "lib.iyi: $rename lib.ri"

for name in UP.IYI Up.Iyi; do
  fresh
  printf '%s' "$hello" > "$name"
  "$RIS" run "$name" > out.txt 2>&1; rc=$?
  refused "ris run $name is refused the same way" out.txt \
    "$name: $rename ${name%.*}.ri"
done

fresh
mkdir -p lib/old .hidden mods
printf '%s' "$hello" > lib/old/x.iyi
printf '%s' "$hello" > .hidden/x.iyi
printf '%s' "$hello" > mods/x.iyi
printf 'module main_test\n\nassert_eq 1, 1\n' > main_test.ri
"$RIS" test . > out.txt 2>&1; rc=$?
say "a .iyi file in lib/, mods/ or a dot directory is not seen" \
  "$([ "$rc" -eq 0 ]; echo $?)"
printf 'module main\n\nimport mods/x\n' > main.ri
"$RIS" build main.ri > out.txt 2>&1; rc=$?
refused "... and refused when imported" out.txt "x.iyi: $rename x.ri"

fresh
printf '%s' "$hello" > main.ri
printf 'module demo\n' > iyi.mod
"$RIS" build main.ri > out.txt 2>&1; rc=$?
refused "iyi.mod without ris.mod is refused" out.txt \
  "rename iyi.mod to ris.mod"
cp iyi.mod ris.mod
"$RIS" build main.ri > out.txt 2>&1; rc=$?
refused "iyi.mod beside ris.mod is refused" out.txt \
  "rename iyi.mod to ris.mod"
rm iyi.mod
: > iyi.sum
"$RIS" build main.ri > out.txt 2>&1; rc=$?
refused "iyi.sum is refused" out.txt "rename iyi.sum to ris.sum"

echo "7.3: IYI_X is not read; RIS_X is"
fresh
mkdir -p libdir cachex cachei
printf 'module shared\n\npub def shared_value : Int32\n  9\nend\n' \
  > libdir/shared.ri
printf 'module main\n\nimport shared::*\n\nputs shared_value\n' > main.ri
notice='IYI_PATH is not read: set RIS_PATH'
RIS_PATH="$REPO/src:$WORK/p/libdir" "$RIS" run main.ri > out.txt 2> err.txt
rc=$?
say "RIS_PATH only: used" \
  "$([ "$rc" -eq 0 ] && grep -qx 9 out.txt; echo $?)"
RIS_PATH="$REPO/src:$WORK/p/libdir" IYI_PATH="$WORK/nowhere" \
  "$RIS" run main.ri > out.txt 2> err.txt; rc=$?
say "RIS_PATH and IYI_PATH: RIS_PATH used, no message" \
  "$([ "$rc" -eq 0 ] && grep -qx 9 out.txt && ! grep -q 'is not read' err.txt
     echo $?)"
IYI_PATH="$REPO/src:$WORK/p/libdir" "$RIS" run main.ri > out.txt 2> err.txt
rc=$?
say "IYI_PATH only: not used, the notice once" \
  "$([ "$rc" -ne 0 ] && [ "$(grep -cxF "$notice" err.txt)" = 1 ]; echo $?)"
IYI_PATH= RIS_PATH="$REPO/src:$WORK/p/libdir" "$RIS" run main.ri \
  > out.txt 2> err.txt; rc=$?
say "IYI_PATH empty: as unset" \
  "$([ "$rc" -eq 0 ] && ! grep -q 'is not read' err.txt; echo $?)"

printf '%s' "$hello" > main.ri
notice='IYI_CACHE_DIR is not read: set RIS_CACHE_DIR'
RIS_CACHE_DIR="$WORK/p/cachex" "$RIS" build main.ri -o m > out.txt 2> err.txt
rc=$?
say "RIS_CACHE_DIR only: used" \
  "$([ "$rc" -eq 0 ] && [ -n "$(ls -A cachex)" ]; echo $?)"
rm -rf cachex/* cachei/*
RIS_CACHE_DIR="$WORK/p/cachex" IYI_CACHE_DIR="$WORK/p/cachei" \
  "$RIS" build main.ri -o m > out.txt 2> err.txt; rc=$?
say "RIS_CACHE_DIR and IYI_CACHE_DIR: RIS's used, no message" \
  "$([ "$rc" -eq 0 ] && [ -n "$(ls -A cachex)" ] && [ -z "$(ls -A cachei)" ] \
     && ! grep -q 'is not read' err.txt; echo $?)"
rm -rf cachex/* cachei/*
env -u RIS_CACHE_DIR IYI_CACHE_DIR="$WORK/p/cachei" \
  "$RIS" build main.ri -o m > out.txt 2> err.txt
rc=$?
say "IYI_CACHE_DIR only: not used, the notice, exit status unchanged" \
  "$([ "$rc" -eq 0 ] && [ -z "$(ls -A cachei)" ] \
     && [ "$(grep -cxF "$notice" err.txt)" = 1 ]; echo $?)"
env -u RIS_CACHE_DIR IYI_CACHE_DIR= \
  "$RIS" build main.ri -o m > out.txt 2> err.txt; rc=$?
say "IYI_CACHE_DIR empty: as unset" \
  "$([ "$rc" -eq 0 ] && ! grep -q 'is not read' err.txt; echo $?)"

"$RIS" env > out.txt 2>&1; rc=$?
say "ris env prints RIS_ names only" \
  "$([ "$rc" -eq 0 ] && grep -q '^RIS_PATH=' out.txt \
     && grep -q '^RIS_CACHE_DIR=' out.txt && ! grep -q '^IYI_' out.txt
     echo $?)"
"$RIS" env RIS_CACHE_DIR > out.txt 2>&1; rc=$?
say "ris env RIS_CACHE_DIR answers it" \
  "$([ "$rc" -eq 0 ] && grep -qxF "$RIS_CACHE_DIR" out.txt; echo $?)"
"$RIS" env IYI_PATH > out.txt 2>&1; rc=$?
refused "ris env IYI_PATH is no such variable" out.txt \
  "no such variable: IYI_PATH"

echo "7.2: module artifacts"
fresh
printf '%s' "$hello" > main.ri
for flag in emit use; do
  mkdir -p d
  "$RIS" build --$flag-iyimod d main.ri > out.txt 2>&1; rc=$?
  refused "--$flag-iyimod is refused with its new name" out.txt \
    "--$flag-iyimod is --$flag-rimod now"
done
: > old.iyimod
"$RIS" build old.iyimod > out.txt 2>&1; rc=$?
refused "a given .iyimod is refused" out.txt \
  "old.iyimod: built by an older compiler; rebuild it"
printf 'module main\n\nimport lib\n' > main.ri
mkdir -p arts && : > arts/lib.iyimod
"$RIS" build --use-rimod arts main.ri > out.txt 2>&1; rc=$?
refused "a found .iyimod is refused" out.txt \
  "lib.iyimod: built by an older compiler; rebuild it"

echo "7.1: what the tools print says ris"
# A lowercase word iyi, outside a type name (Iyi*) or a __iyi_ symbol.
iyi_word() {
  grep -qP '(?<![A-Za-z0-9_])iyi(?![A-Za-z0-9_])' "$1"
}
fresh
printf 'module main\n\nraise "boom"\n' > panic.ri
"$RIS" run panic.ri > out.txt 2>&1; rc=$?
say "a panic's output names no iyi" \
  "$([ "$rc" -ne 0 ] && grep -q boom out.txt && ! iyi_word out.txt; echo $?)"
printf 'module main\n\nputs undefined_thing(1)\n' > bad.ri
"$RIS" build bad.ri > out.txt 2>&1; rc=$?
say "a refused program's output names no iyi" \
  "$([ "$rc" -eq 1 ] && grep -q undefined_thing out.txt && ! iyi_word out.txt
     echo $?)"
(cd "$REPO" && "$RIS" doc std/base64) > out.txt 2>&1; rc=$?
say "ris doc of a std module names no iyi" \
  "$([ "$rc" -eq 0 ] && [ -s out.txt ] && ! iyi_word out.txt; echo $?)"

echo "the repository"
left="$(cd "$REPO" && git ls-files '*.iyi' ':!doc/archive' ':!doc/reference')"
say "no tracked .iyi file outside doc/archive and doc/reference" \
  "$([ -z "$left" ]; echo $?)"

if [ "$status" -eq 0 ]; then
  echo "PASS: ri_only"
else
  echo "FAIL: ri_only"
fi
exit "$status"
