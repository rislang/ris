#!/usr/bin/env bash
# ris's own checks: every program under test/ris/refused must be refused by
# the compiler with the expected message, test/ris/allowed.ri must compile
# and run, the fibers test must read back what each fiber wrote, a tape must
# grow past its first mapping in whole 64 KiB grains and refuse an index out
# of range, and the respond sample must print its known checksum.
#
#   bash test/ris/check.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
RIS=${RIS:-./bin/ris}
status=0

expect() {
  local name=$1 needle=$2 out
  out=$("$RIS" build --no-codegen "test/ris/refused/$name.ri" 2>&1)
  if [ $? -ne 0 ] && grep -qF -- "$needle" <<<"$out"; then
    printf 'refused  %s\n' "$name"
  else
    printf 'FAILED   %s: expected an error containing: %s\n' "$name" "$needle"
    status=1
  fi
}

expect class_field   "holds the tape type"
expect struct_field  "is a struct that is not @[OnTape]"
expect class_var     "the class variable"
expect generic_array "Array("
expect proc_capture  "this block becomes a proc"
expect outer_var     "is a variable of the code around this Tape.scope"
expect scope_value   "undefined method 'id' for Nil"
expect yield_escape "is a variable of the code around this Tape.scope"
expect yield_scope_escape "is a variable of the code around this Tape.scope"
expect return_escape "cannot return a tape value out of its Tape.scope"
expect break_escape "cannot break a tape value out of its Tape.scope"
expect yield_break_escape "cannot break a tape value out of its Tape.scope"

expect return_escape 'Copy the text with `.to_s`'
expect outer_var 'copy contained TapeString values with `.to_s`'
expect owned_cache "to be String, not TapeString"

expect local_outer "is a variable of the code around this Tape.local"
expect local_mutate "cannot use outer tape value"
expect local_self 'cannot use outer tape value `self`'
expect local_return "cannot return a tape value"
expect local_break "cannot break a tape value"
expect local_yield_break "cannot break a tape value"
out=$("$RIS" run test/ris/local.ri 2>&1)
if [ "$out" = 'PASS: local isolation, reuse, nested scopes, borrowed text, retained copy and early exits' ]; then echo "runs     local"; else echo "FAILED   local: $out"; status=1; fi

out=$("$RIS" run test/ris/local_cleanup.ri 2>/dev/null)
if [ "$out" = 'PASS: local panic cleanup and fiber switching' ]; then echo "runs     local_cleanup"; else echo "FAILED   local_cleanup: $out"; status=1; fi

# Cleanup keeps LIFO order on early exits, panic and explicit exit.
out=$("$RIS" run test/ris/cleanup_order.ri 2>&1)
if [ "$out" = $'inner return\nouter return\n7\nnested\ninner break\nouter break\ninner return\nouter return\n7\ntrue\ntrue' ]; then echo "runs     cleanup_order"; else echo "FAILED   cleanup_order: $out"; status=1; fi
out=$("$RIS" run test/ris/cleanup_allocations.ri 2>&1)
if [ "$out" = $'no GC allocation per scope\ntrue' ]; then echo "runs     cleanup_allocations"; else echo "FAILED   cleanup_allocations: $out"; status=1; fi
out=$("$RIS" run test/ris/fibers/cleanup_panic.ri 2>/dev/null)
if [ "$?" = 0 ] && [ "$out" = $'nested panic\ninner panic\nouter panic\ntrue\ntrue\nscope after panic' ]; then echo "runs     cleanup_panic"; else echo "FAILED   cleanup_panic: $out"; status=1; fi
out=$("$RIS" run test/ris/cleanup_exit.ri 2>&1)
if [ "$?" = 3 ] && [ "$out" = $'inner exit\nouter exit' ]; then echo "runs     cleanup_exit"; else echo "FAILED   cleanup_exit: $out"; status=1; fi

out=$("$RIS" run test/ris/zero_capacity.ri 2>&1)
if [ "$out" = $'123\n789\n456\nABC' ]; then echo "runs     zero_capacity"; else echo "FAILED   zero_capacity: $out"; status=1; fi

out=$("$RIS" run test/ris/scope_cleanup.ri 2>&1)
if [ "$out" = $'1\ntrue\ntrue\ntrue\nC\ntrue' ]; then echo "runs     scope_cleanup"; else echo "FAILED   scope_cleanup: $out"; status=1; fi

out=$("$RIS" run test/ris/lifetime_flow.ri 2>&1)
if [ "$out" = $'A\nA\nA\nA' ]; then echo "runs     lifetime_flow"; else echo "FAILED   lifetime_flow: $out"; status=1; fi

out=$("$RIS" run test/ris/allowed.ri 2>&1)
if [ "$out" = $'2\na' ]; then echo "runs     allowed"; else echo "FAILED   allowed: $out"; status=1; fi

out=$("$RIS" run test/ris/fibers/interleave.ri 2>&1)
if [ "$out" = $'fiber A wrong: 0\nfiber B wrong: 0' ]; then echo "runs     fibers/interleave"; else echo "FAILED   fibers/interleave: $out"; status=1; fi
out=$("$RIS" run test/ris/fibers/many.ri 2>&1)
if [ "$out" = "1000 tapes at once, sum 499500" ]; then echo "runs     fibers/many"; else echo "FAILED   fibers/many: $out"; status=1; fi

out=$("$RIS" run test/ris/grow.ri 2>&1)
if [ "$out" = $'round 1: 100 MiB intact, before 499500, after 7\nround 2: 100 MiB intact, before 999000, after 14' ]; then echo "runs     grow"; else echo "FAILED   grow: $out"; status=1; fi

out=$("$RIS" run test/ris/grain.ri 2>&1)
if [ "$out" = 'PASS: tape mappings are whole 64 KiB grains' ]; then echo "runs     grain"; else echo "FAILED   grain: $out"; status=1; fi

out=$("$RIS" run test/ris/bounds.ri 2>&1)
if grep -qF $'10 30 30' <<<"$out" && grep -qF "index 3 out of range for 3 elements" <<<"$out"; then echo "runs     bounds"; else echo "FAILED   bounds: $out"; status=1; fi

out=$("$RIS" run test/ris/owned.ri 2>&1)
if [ "$out" = 'PASS: explicit owned copy, typed cache boundary, UTF-8, empty text and scope reuse' ]; then echo "runs     owned"; else echo "FAILED   owned: $out"; status=1; fi

out=$("$RIS" run test/ris/writer.ri 2>&1)
if [ "$out" = '0 -42 9223372036854775807 -9223372036854775808 a&amp;b&lt;c&gt;&quot;d&#39;e <b>' ]; then echo "runs     writer"; else echo "FAILED   writer: $out"; status=1; fi

out=$("$RIS" run samples/ris/hello.ri 2>&1)
if [ "$out" = $'Hello from ris, order 1\ntotal 1649' ]; then echo "runs     samples/ris/hello"; else echo "FAILED   samples/ris/hello: $out"; status=1; fi

exe=$(mktemp)
if "$RIS" build --release -o "$exe" samples/ris/respond.ri >/dev/null 2>&1 && [ "$("$exe" | tail -1)" = "7480137599999527189" ]; then
  echo "runs     samples/ris/respond (checksum matches)"
else
  echo "FAILED   samples/ris/respond"; status=1
fi
rm -f "$exe"
exit $status
