#!/usr/bin/env bash
# Runs the `std/box` spec blocks plain and --release, and proves a broken
# unbox is caught.
#
#     bash test/cli/std_box_exercise.sh
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

# The search path is a list, and the byte between its entries is the
# platform's: `;` where a drive letter already owns the colon.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT) PSEP=';' ;;
  *) PSEP=':' ;;
esac

# the patches and oracles below are written in python, and windows answers
# `python3` with a store stub that prints and exits rather than running it, so
# the interpreter is measured here instead of assumed.
PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys' >/dev/null 2>&1; then
    PY="$candidate"
    break
  fi
done

RIS="${RIS:-$REPO/bin/ris}"
mkdir -p "$REPO/test/cli/.work"
WORK="$(mktemp -d "$REPO/test/cli/.work/XXXXXX")"
# A native compiler cannot resolve this shell's own path mapping: a search
# path built from `pwd` is `/c/...` and finds no prelude at all, and a
# scratch directory named `/tmp/tmp.X` is silently ignored on that path, so
# the patched copy is never read and the proof that a check can fail quietly
# stops proving it.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT)
    REPO="$(cygpath -m "$REPO")"
    WORK="$(cygpath -m "$WORK")"
    ;;
esac

trap 'rm -rf "$WORK"' EXIT

status=0
export RIS_PATH="$REPO/src${PSEP}$REPO/samples/ris"

build_and_run() {
  local label="$1" name="$2"
  shift 2
  if ! "$RIS" build --spec "$@" -o "$WORK/$name" "$REPO/src/std/box.ri" \
       >"$WORK/$name.build.log" 2>&1; then
    echo "$label: build failed"
    tail -12 "$WORK/$name.build.log"
    status=1
    return 1
  fi
  "$WORK/$name" >"$WORK/$name.out" 2>&1
  local exit_code=$?
  sed 's/^/  /' "$WORK/$name.out"
  if [ "$exit_code" -ne 0 ] && [ "$exit_code" -ne 77 ]; then
    echo "$label: exited $exit_code"
    status=1
    return 1
  fi
  if [ "$exit_code" -eq 77 ] &&
     ! grep -q 'todo  spec box.3 ' "$WORK/$name.out"; then
    echo "$label: unexpected todo exit"
    status=1
    return 1
  fi
  return 0
}

echo "== the std/box blocks, plain build"
build_and_run "plain" box-plain
if ! grep -q "ok  spec box.1 " "$WORK/box-plain.out" 2>/dev/null; then
  echo "plain: missing pass sentinel"
  status=1
fi

echo
echo "== every box block reported"
for phrase in "spec box.1 " "spec box.2 " "spec box.3 "; do
  if ! grep -q "$phrase" "$WORK/box-plain.out" 2>/dev/null; then
    echo "  missing section: $phrase"
    status=1
  fi
done
[ "$status" -eq 0 ] && echo "  sections reported"

echo
echo "== the same blocks with optimisation on (--release)"
build_and_run "release" box-release --release >/dev/null
if ! grep -q "ok  spec box.2 " "$WORK/box-release.out" 2>/dev/null; then
  echo "release: missing pass sentinel"
  status=1
fi

echo
echo "== proving the checks can fail when the module is broken"
mkdir -p "$WORK/patched/std"
if [ -z "$PY" ]; then
  echo "  no python3 on this machine, so the broken-module proof is unmeasured"
elif ! "$PY" - <<PY
from pathlib import Path
src = Path("$REPO/src/std/box.ri").read_text()
old = 'pointer.as(self).object'
if old not in src:
    raise SystemExit("patch site missing")
Path("$WORK/patched/std/box.ri").write_text(src.replace(old, 'raise "unbox discarded"', 1))
PY
then
  echo "  the patch did not apply"
  status=1
elif ! RIS_PATH="$WORK/patched${PSEP}$REPO/src${PSEP}$REPO/samples/ris" "$RIS" build --spec -o "$WORK/mut.bin" "$WORK/patched/std/box.ri" >"$WORK/mut.out" 2>&1; then
  echo "  the broken copy did not compile"
  sed -n '1,6p' "$WORK/mut.out"
  status=1
elif "$WORK/mut.bin" >"$WORK/mut.out" 2>&1 ||
     ! grep -q "spec box.1 " "$WORK/mut.out"; then
  echo "  the blocks PASSED on a broken module"
  status=1
else
  echo "  a broken box is caught"
fi

echo
if [ "$status" -eq 0 ]; then
  echo "the std/box blocks hold"
else
  echo "the std/box blocks did not hold"
fi
exit $status
