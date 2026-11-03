#!/bin/sh
# Builds each trial program, runs it and compares its output with
# expected/NAME.txt. Usage: samples/ris/trial/run.sh (from anywhere).
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$here" || exit 2

args_wc="data/words.txt"
args_json_edit="data/config.json $work/out.json"
args_ls="-l -e .txt data"
args_csv_sum="data/sales.csv"
args_http_trial=""
args_tuple_order=""

failed=0
for name in wc json_edit ls csv_sum http_trial tuple_order; do
  if ! "$root/bin/ris" build -o "$work/$name" "$name.ri" >"$work/log" 2>&1; then
    echo "FAILED $name: does not build"
    tail -5 "$work/log"
    failed=$((failed + 1))
    continue
  fi
  eval "args=\$args_$name"
  timeout 30 "$work/$name" $args >"$work/$name.out" 2>&1
  if cmp -s "$work/$name.out" "expected/$name.txt"; then
    echo "ok $name"
  else
    echo "FAILED $name"
    diff "expected/$name.txt" "$work/$name.out" | head -10
    failed=$((failed + 1))
  fi
done
if ! sh "$root/test/ris/http_doc.sh"; then
  failed=$((failed + 1))
fi
echo "FAILED count: $failed"
[ "$failed" -eq 0 ]
