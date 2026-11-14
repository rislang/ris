#!/usr/bin/env bash
# Builds at once share one cache directory. A program whose macro `run`s a
# helper keeps the helper in its own cache directory, and every build keeps
# only the ten newest directories. The helper's directory held no lock, so
# another build's cleanup deleted it between its compile and its run:
# "Error: .../helper.ri/macro_run: No such file or directory". This runs
# builds of the helper's program, of each other's sources and of a dozen
# distinct programs in parallel loops on one RIS_CACHE_DIR; every build
# must pass.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RIS="${RIS:-$REPO/bin/ris}"
mkdir -p "$REPO/test/cli/.work"
WORK="$(mktemp -d "$REPO/test/cli/.work/XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export RIS_CACHE_DIR="$WORK/cache"
ROUNDS="${ROUNDS:-3}"

cd "$WORK"
printf 'puts "42"\n' > helper.ri
for m in 1 2 3; do
  printf 'puts {{ run("./helper.ri").stringify }}\n' > "main$m.ri"
done
for i in $(seq 1 30); do
  printf 'puts %d\n' "$i" > "p$i.ri"
done

# One loop per source; the main loops also touch the helper so that it is
# relinked now and then, and the plain loops churn the cache past ten.
loop() {
  local src=$1 n=$2
  for r in $(seq 1 "$ROUNDS"); do
    if [[ $src == main* ]]; then touch helper.ri; fi
    if ! "$RIS" build "$src" -o "out-$src-$n" > "log-$src-$n-$r" 2>&1; then
      echo "FAIL: $src (loop $n, round $r)"
      tail -5 "log-$src-$n-$r"
      return 1
    fi
  done
}

pids=()
for m in 1 2 3; do
  loop "main$m.ri" a & pids+=($!)
  loop "main$m.ri" b & pids+=($!)
done
for i in $(seq 1 30); do
  loop "p$i.ri" a & pids+=($!)
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
for m in 1 2 3; do
  [[ $(./"out-main$m.ri-a") == 42 ]] || { echo "FAIL: main$m output"; fail=1; }
done

# The cleanup side, without timing: a directory whose `macro_run.lock` a
# compiler holds shared survives eleven newer builds.
held="$RIS_CACHE_DIR/held"
mkdir -p "$held"
touch -d '2000-01-01' "$held"
flock -s "$held/macro_run.lock" sleep 30 & holder=$!
sleep 1
for i in $(seq 1 12); do "$RIS" build "p$i.ri" -o "q$i" > /dev/null 2>&1; done
[[ -d $held ]] || { echo "FAIL: cleanup deleted a held macro directory"; fail=1; }
kill "$holder" 2>/dev/null || true

if (( fail )); then echo "cache_concurrency: FAIL"; exit 1; fi
echo "cache_concurrency: ok"
