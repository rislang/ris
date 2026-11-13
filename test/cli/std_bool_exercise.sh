#!/usr/bin/env bash
# Runs the `std/bool` spec blocks plain and --release, and proves a broken
# hash is caught by them.
#
#     bash test/cli/std_bool_exercise.sh
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

IYI="${IYI:-$REPO/bin/ris}"
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
export IYI_PATH="$REPO/src${PSEP}$REPO/samples/iyi"

build_and_run() {
  local label="$1" name="$2"
  shift 2
  if ! "$IYI" build --spec "$@" -o "$WORK/$name" "$REPO/src/std/bool.iyi" \
       >"$WORK/$name.build.log" 2>&1; then
    echo "$label: build failed"
    tail -12 "$WORK/$name.build.log"
    status=1
    return 1
  fi
  "$WORK/$name" >"$WORK/$name.out" 2>&1
  local exit_code=$?
  sed 's/^/  /' "$WORK/$name.out"
  if [ "$exit_code" -ne 0 ]; then
    echo "$label: exited $exit_code"
    status=1
    return 1
  fi
  return 0
}

echo "== the std/bool spec blocks, plain build"
build_and_run "plain" bool-plain
for block in bool.1 bool.2 bool.3; do
  if ! grep -q "ok  spec $block " "$WORK/bool-plain.out" 2>/dev/null; then
    echo "  plain: spec $block not reported ok"
    status=1
  fi
done

echo
echo "== the same program with optimisation on (--release)"
build_and_run "release" bool-release --release >/dev/null
if ! grep -q "ok  spec bool.3 " "$WORK/bool-release.out" 2>/dev/null; then
  echo "release: spec bool.3 not reported ok"
  status=1
fi

echo
echo "== proving the checks can fail when the module is broken"
mkdir -p "$WORK/patched/std"
if [ -z "$PY" ]; then
  echo "  no python3 on this machine, so the broken-module proof is unmeasured"
elif ! "$PY" - <<PY
from pathlib import Path
src = Path("$REPO/src/std/bool.iyi").read_text()
old = 'self ? 1231 : 1237'
if old not in src:
    raise SystemExit("patch site missing")
Path("$WORK/patched/std/bool.iyi").write_text(src.replace(old, '1231', 1))
PY
then
  echo "  the patch did not apply"
  status=1
elif ! IYI_PATH="$WORK/patched${PSEP}$REPO/src${PSEP}$REPO/samples/iyi" "$IYI" build --spec -o "$WORK/mut.bin" "$WORK/patched/std/bool.iyi" >"$WORK/mut.out" 2>&1; then
  echo "  the broken copy did not compile"
  sed -n '1,6p' "$WORK/mut.out"
  status=1
elif "$WORK/mut.bin" >"$WORK/mut.out" 2>&1; then
  echo "  the spec blocks PASSED on a broken module"
  status=1
elif ! grep -q "BROKEN  spec bool.3" "$WORK/mut.out"; then
  echo "  failed, but not in spec bool.3"
  status=1
else
  echo "  a broken bool is caught"
fi

echo
if [ "$status" -eq 0 ]; then
  echo "the std/bool exercise holds"
else
  echo "the std/bool exercise did not hold"
fi
exit $status
