#!/usr/bin/env bash
# Drives test/cli/server_load.ri: the shape every server has — a fiber per
# connection, both halves parked on the poller, a collection in the
# middle — and the two things that shape used to break.
#
#     bash test/cli/server_load.sh
#
# Three steps, and one is a failure proof, because a gate that cannot
# fail is not a gate:
#
#   1. The program holds, plain build: two hundred connections answered,
#      the collector runs while fibers are parked, nothing is damaged,
#      and the connections ran on a handful of stacks rather than two
#      hundred.
#   2. The same, release.
#   3. Failure proof: a finished fiber's stack not handed back, and the
#      two hundred connections take two hundred mappings.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

# The search path is a list, and the byte between its entries is the
# platform's: `;` where a drive letter already owns the colon.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT) PSEP=';' ;;
  *) PSEP=':' ;;
esac

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

cd "$WORK" || exit 1

step() { echo "== $1"; }

# Windows has a poller and sockets now — a completion port under the same
# `IyiScheduler`, and `std/socket`'s Winsock arm over it — so this drives
# there too. The line it used to print, that the poller is Linux's and
# darwin's, was true when it was written and stopped being true without
# anything here noticing.
case "$(uname -s)" in
  Linux | Darwin | MINGW* | MSYS* | CYGWIN* | Windows_NT) ;;
  *) echo "server load: this platform has no poller to drive; nothing to measure here"; exit 0 ;;
esac

step "a server's shape, plain build"
if ! "$RIS" build "$REPO/test/cli/server_load.ri" -o server > build.log 2>&1; then
  cat build.log; exit 1
fi
if ! timeout 300 ./server > answers.txt 2>&1; then
  echo "the run failed:"; cat answers.txt; exit 1
fi
grep -q 'every property held' answers.txt || { cat answers.txt; exit 1; }
grep -E '^(collections|answers|stacks|canary) ' answers.txt | sed 's/^/  /'

step "a server's shape, release build"
if ! "$RIS" build --release "$REPO/test/cli/server_load.ri" -o server-release > build-release.log 2>&1; then
  cat build-release.log; exit 1
fi
if ! timeout 300 ./server-release > answers-release.txt 2>&1; then
  echo "the release run failed:"; cat answers-release.txt; exit 1
fi
grep -q 'every property held' answers-release.txt || { cat answers-release.txt; exit 1; }

mkdir -p patched/ris

# The proof that hid the poller's buffer from the collector is gone with
# the collector: ris has no heap to collect.

step "failure proof: a stack nobody hands back is a stack per connection"
cp "$REPO"/src/ris/*.ri patched/ris/
sed -e 's/^    fiber\.release_stack$/    # the stack is not handed back/' \
    "$REPO/src/ris/concurrency.ri" > patched/ris/concurrency.ri
cmp -s patched/ris/concurrency.ri "$REPO/src/ris/concurrency.ri" && {
  echo "the sed found nothing to change"; exit 1; }
if ! RIS_PATH="$WORK/patched${PSEP}$REPO/src" "$RIS" build "$REPO/test/cli/server_load.ri" -o noreuse > build-noreuse.log 2>&1; then
  cat build-noreuse.log; exit 1
fi
timeout 300 ./noreuse > noreuse.txt 2>&1
code=$?
if [ "$code" -ne 1 ] || ! grep -q 'the stacks were not reused' noreuse.txt; then
  echo "the stack-reuse check did not fire (exit $code):"; tail -3 noreuse.txt; exit 1
fi
printf '  exits 1 at "%s"\n' "$(grep -m1 'the stacks were not reused' noreuse.txt | sed 's/^ris: panic: FAIL: //')"
echo "workdir $WORK"
echo "server load: every step held"
exit 0
