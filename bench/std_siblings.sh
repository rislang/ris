#!/usr/bin/env bash
# Runs the std modules' own exercises - every `bench/std_<module>_exercise.sh`
# but `std_exercise.sh` itself - or one shard of them.
#
#     bash bench/std_siblings.sh          # all of them
#     bash bench/std_siblings.sh 2 4      # the second of four shards
#
# Shard K of N is every exercise whose place in the list, counted from one,
# leaves K when divided by N, N for none, past the shards the slowest have
# to themselves (SLOWEST): interleaved rather than cut in runs, so the slow
# ones (std/http's proofs, std/big's, the crypto oracles) spread out
# instead of landing in one shard. `bench/std_exercise.sh` runs all of them
# after its own sections; CI runs the shards side by side, because one after
# another they outgrew the hour the job had - and the sum is the same set,
# which the shard header line says so a log can be added up.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
shard="${1:-1}"
shards="${2:-1}"
case "$shard$shards" in
  *[!0-9]*)
    echo "usage: bash bench/std_siblings.sh [K N]: K and N are numbers"
    exit 2
    ;;
esac
if [ "$shards" -lt 1 ] || [ "$shard" -lt 1 ] || [ "$shard" -gt "$shards" ]; then
  echo "usage: bash bench/std_siblings.sh [K N]: 1 <= K <= N"
  exit 2
fi

# Each sibling has SIBLING_MINUTES (50: std/http's, the slowest, takes 30
# on Linux, 33 on darwin and past 35 on Windows) and is stopped past them,
# failing by name. A hang left to the
# job's own limit cancelled the job, and a cancelled job keeps no log: a
# Windows shard ran 65 minutes and said nothing of where it stopped.
limit=$(( ${SIBLING_MINUTES:-50} * 60 ))
bounded=""
command -v timeout >/dev/null 2>&1 && bounded="timeout -k 30 $limit"

# The slowest each have a shard of their own, and the rest are interleaved
# over the others: sorted by name, std/http (30 minutes on Linux), std/big
# (15 to 23) and std/tls (22) fell into shards that were full without
# them, and those ran past their limit. With too few shards for that, all
# share. CI's std/tls throughput step runs in std/tls's shard, the third.
SLOWEST="std_http_exercise.sh std_big_exercise.sh std_tls_exercise.sh"
alone=0
for name in $SLOWEST; do
  [ -f "$REPO/bench/$name" ] && alone=$((alone + 1))
done
[ "$alone" -lt "$shards" ] || alone=0

status=0
place=0
ran=""
for sibling in "$REPO"/bench/std_*_exercise.sh; do
  [ -f "$sibling" ] || continue
  [ "$(basename "$sibling")" = "std_exercise.sh" ] && continue
  place=$((place + 1))
  slow=0
  i=0
  for name in $SLOWEST; do
    [ -f "$REPO/bench/$name" ] || continue
    i=$((i + 1))
    [ "$(basename "$sibling")" = "$name" ] && slow=$i
  done
  if [ "$alone" -gt 0 ] && [ "$slow" -gt 0 ]; then
    [ "$slow" -eq "$shard" ] || continue
  elif [ "$alone" -gt 0 ]; then
    [ $(((place - 1) % (shards - alone) + 1 + alone)) -eq "$shard" ] || continue
  else
    [ $(((place - 1) % shards + 1)) -eq "$shard" ] || continue
  fi
  ran="$ran $(basename "$sibling" .sh)"
  echo "-- running sibling: $(basename "$sibling")"
  $bounded bash "$sibling"
  code=$?
  if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
    echo "FAIL: sibling $(basename "$sibling") had not finished in $((limit / 60)) minutes, and was stopped"
    status=1
  elif [ "$code" -ne 0 ]; then
    echo "FAIL: sibling $(basename "$sibling") failed"
    status=1
  fi
done

echo
echo "== shard $shard of $shards: $(echo $ran | wc -w | tr -d ' ') of $place sibling exercises"
[ -n "$ran" ] || echo "  (none in this shard)"
exit "$status"
