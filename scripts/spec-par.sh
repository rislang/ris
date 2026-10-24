#!/usr/bin/env bash
# ris: every spec suite at once, split over the cores, then
# test/ris/check.sh. Each suite runs in parts (SPEC_SPLIT=r%m), each part
# with a tmp and a cache of its own; an example that fails in its part is
# run again alone, and only one that fails alone too is a failure (some,
# such as `Spec hooks`, need the whole suite). Build flags as for make:
#
#   mini 'scripts/spec-par.sh LLVM_CONFIG=... FLAGS=--mcpu=znver3'
#
# CORES (default: all) sets how many parts run at once.
set -u
cd "$(dirname "$0")/.."
cores=${CORES:-$(nproc)}
out=spec-out
start=$(date +%s)
make -j"$cores" "$@" .build/std_spec .build/compiler_spec \
  .build/primitives_spec .build/cli_spec ris check_daemon_matches \
  > spec-build.log 2>&1 || { tail -30 spec-build.log; exit 1; }
echo "build   $(( $(date +%s) - start ))s"

# Tests leave directories they cannot read: let them go.
clean() { chmod -R u+rwx "$@" 2>/dev/null; rm -rf "$@"; }
clean $out; mkdir -p $out

# suite parts: run *suite* in *parts* parts, in the background.
run() {
  local suite=$1 parts=$2 r dir tmp
  for r in $(seq 0 $((parts - 1))); do
    dir=$out/$suite-$r tmp=/tmp/rs-${suite%%_*}-$r
    clean "$tmp"; mkdir -p "$dir" "$tmp/tmp" "$tmp/cache"
    ( TMPDIR=$tmp/tmp IYI_CACHE_DIR=$tmp/cache CRYSTAL_CACHE_DIR=$tmp/cache \
        SPEC_SPLIT=$r%$parts .build/$suite --order=random > "$dir/log" 2>&1
      echo $? > "$dir/rc" ) &
  done
}

# compiler_spec is the long one: it gets three of every four cores.
big=$(( cores * 3 / 4 )); big=$(( big > 0 ? big : 1 ))
rest=$(( cores - big - 2 )); rest=$(( rest > 0 ? rest : 1 ))
t=$(date +%s)
run compiler_spec $big; run std_spec $rest
run primitives_spec 1; run cli_spec 1
wait
echo "specs   $(( $(date +%s) - t ))s"

# The examples that failed in their part, run again one at a time.
status=0
for suite in compiler_spec std_spec primitives_spec cli_spec; do
  grep -ahoE '^crystal spec [^ ]+:[0-9]+' $out/$suite-*/log \
    | sed 's/^crystal spec //' | sort -u > $out/$suite.failed
  while read -r at; do
    tmp=/tmp/rs-again; clean "$tmp"; mkdir -p "$tmp/tmp" "$tmp/cache"
    if TMPDIR=$tmp/tmp IYI_CACHE_DIR=$tmp/cache \
       CRYSTAL_CACHE_DIR=$tmp/cache .build/$suite --location "$at" \
       > $out/again.log 2>&1; then
      echo "alone ok  $suite $at"
    else
      echo "FAILED    $suite $at"; status=1
    fi
  done < $out/$suite.failed
  # A part that stopped without a summary crashed: that is a failure too.
  for dir in $out/$suite-*; do
    grep -aqE '^[0-9]+ examples' "$dir/log" ||
      { echo "CRASHED   $(basename "$dir")"; status=1; }
  done
done
awk '/^[0-9]+ examples/ {e += $1; f += $3; x += $5}
  END {print e " examples, " f " failures and " x " errors in parts"}' \
  $out/*-*/log

clean /tmp/rs-*
bash test/ris/check.sh > $out/check.log 2>&1 || status=1
echo "check   $(grep -c FAILED $out/check.log) failed (test/ris/check.sh)"
echo "total   $(( $(date +%s) - start ))s"
exit $status
