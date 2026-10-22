#!/usr/bin/env bash
# ris's own checks: every program under test/ris/refused must be refused by
# the compiler with the expected message, test/ris/allowed.ri must compile
# and run, the fibers test must read back what each fiber wrote, a tape must
# grow past its first mapping in whole 64 KiB grains and refuse an index out
# of range, a Tape::Tree must step over subtrees, and the respond sample must
# print its known checksum.
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
expect integer_text  "integer / in text gives a Float"
expect outer_var     "is a variable of the code around this tape block"
expect scope_value   "undefined method 'id' for Nil"
expect yield_escape "is a variable of the code around this tape block"
expect yield_scope_escape "is a variable of the code around this tape block"
expect return_escape "cannot return a tape value out of its tape block"
expect break_escape "cannot break a tape value out of its tape block"
expect yield_break_escape "cannot break a tape value out of its tape block"

expect return_escape 'Copy the text with `.to_heap`'
expect outer_var '`to_heap` copies a Tape::String or Tape::Array'
expect owned_cache "to be String, not Tape::String"

expect local_outer "is a variable of the code around this local_tape block"
expect local_mutate "cannot use outer tape value"
expect local_self 'cannot use outer tape value `self`'
expect local_return "cannot return a tape value"
expect local_break "cannot break a tape value"
expect local_yield_break "cannot break a tape value"
expect raw_pointer      "to_unsafe\` of a Tape::String outside a @[TapeUnsafe] def"
expect raw_view         "Tape::String.new(pointer, size)\` outside a @[TapeUnsafe] def"
expect std/tape_unsafe_codec "reaches no \`lib\` fun or system call"
expect std/tape_unsafe_no_pointer "hands no tape pointer to the OS"
expect tape_pointer "\`unsafe_append\` outside a @[TapeUnsafe] def"
expect std/tape_pointer_codec "the pointer \`unsafe_append\` yields reaches no"
expect writer_grow      "private method 'grow' called for Tape::String::Writer"
expect tree_entry       "private constant Tape::Tree::Entry(T) referenced"
expect array_grow       "private method 'grow' called for Tape::Array(T)"
expect heap_copy \
  "\`to_s\` of a Tape::String outside a @[TapeToHeap] def copies"
expect heap_copy_top \
  "\`to_s\` of a Tape::String outside a @[TapeToHeap] def"
expect heap_interpolation \
  "Interpolating a Tape::String outside a @[TapeToHeap]"
expect heap_builder     "Writing a Tape::String into a String::Builder"
expect refill           "\`@items\` is given a new Tape::Array in \`take\`"
expect heap_copy        "tape -> heap -> tape pays this at every turn"
expect heap_memory      "Writing a Tape::String into a String::Builder or"
expect heap_memory_print "Writing a Tape::String into a Std::Io::Memory"
expect not_flat "Holder is not flat"
expect check_free "\`first\` is @[CheckFree], and this \`[]\` checks"
expect heap_escape_helper \
  "\`to_s\` of a Tape::String outside a @[TapeToHeap] def copies"


out=$("$RIS" run test/ris/escape.ri 2>&1)
if [ "$out" = 'abc' ]; then
  echo "runs     escape"
else
  echo "FAILED   escape: $out"
  status=1
fi

# Cleanup keeps LIFO order on early exits, panic and explicit exit.
out=$("$RIS" run test/ris/local.ri 2>&1)
if [ "$out" = 'PASS: local isolation, reuse, nested scopes, borrowed text, retained copy and early exits' ]; then echo "runs     local"; else echo "FAILED   local: $out"; status=1; fi
out=$("$RIS" run test/ris/local_cleanup.ri 2>/dev/null)
if [ "$out" = 'PASS: local panic cleanup and fiber switching' ]; then echo "runs     local_cleanup"; else echo "FAILED   local_cleanup: $out"; status=1; fi
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

out=$("$RIS" run --release test/ris/fibers/threads_spawn.ri 2>&1)
if [ "$out" = 'PASS: 4 threads, 32,000 tasks, collected throughout' ]; then echo "runs     fibers/threads_spawn"; else echo "FAILED   fibers/threads_spawn: $out"; status=1; fi

out=$("$RIS" run test/ris/fibers/spares.ri 2>&1)
if [ "$out" = $'warm: 4096 KiB written again\n8388608\ntrimmed' ]; then echo "runs     fibers/spares"; else echo "FAILED   fibers/spares: $out"; status=1; fi

out=$("$RIS" run test/ris/tape_string.ri 2>&1)
if grep -qF 'read through the bounds' <<<"$out" && grep -qF 'index 11 out of range for 11 bytes' <<<"$out"; then echo "runs     tape_string"; else echo "FAILED   tape_string: $out"; status=1; fi

out=$("$RIS" run test/ris/grow.ri 2>&1)
if [ "$out" = $'round 1: 100 MiB intact, before 499500, after 7\nround 2: 100 MiB intact, before 999000, after 14' ]; then echo "runs     grow"; else echo "FAILED   grow: $out"; status=1; fi

out=$("$RIS" run test/ris/grain.ri 2>&1)
if [ "$out" = 'PASS: tape mappings are whole 64 KiB grains' ]; then echo "runs     grain"; else echo "FAILED   grain: $out"; status=1; fi

out=$("$RIS" run test/ris/bounds.ri 2>&1)
if grep -qF $'10 25 35 35' <<<"$out" && grep -qF "index 3 out of range for 3 elements" <<<"$out"; then echo "runs     bounds"; else echo "FAILED   bounds: $out"; status=1; fi

out=$("$RIS" run test/ris/stream.ri 2>&1)
if grep -qF '7 1,2,5,6 3,4 0 7' <<<"$out" && grep -qF "Tape::Tree#close: 2 is not open" <<<"$out"; then echo "runs     stream"; else echo "FAILED   stream: $out"; status=1; fi

out=$("$RIS" run test/ris/owned.ri 2>&1)
if [ "$out" = 'PASS: explicit owned copy, typed cache boundary, UTF-8, empty text and scope reuse' ]; then echo "runs     owned"; else echo "FAILED   owned: $out"; status=1; fi

out=$("$RIS" run test/ris/writer.ri 2>&1)
if [ "$out" = '0 -42 9223372036854775807 -9223372036854775808 a&amp;b&lt;c&gt;&quot;d&#39;e <b>' ]; then echo "runs     writer"; else echo "FAILED   writer: $out"; status=1; fi

# Two pieces, String or on the tape, go out in one socket write.
out=$("$RIS" run test/ris/tape_primitives.ri 2>&1)
if [ "$out" = 'PASS: write_bytes, shift and Tape::Scanner' ]; then echo "runs     tape_primitives"; else echo "FAILED   tape_primitives: $out"; status=1; fi
out=$("$RIS" run test/ris/socket_pair.ri 2>&1)
if [ "$out" = 'PASS: two pieces in one write, String and on the tape, 1 MiB' ]; then echo "runs     socket_pair"; else echo "FAILED   socket_pair: $out"; status=1; fi
out=$("$RIS" run test/ris/socket_pieces.ri 2>&1)
if [ "$out" = 'PASS: 203 pieces in order, empty ones and 1 MiB among them' ]; then echo "runs     socket_pieces"; else echo "FAILED   socket_pieces: $out"; status=1; fi
out=$("$RIS" run test/ris/answer.ri 2>&1)
if [ "$out" = 'PASS: read and answered on the tape, fast path and not' ]; then echo "runs     answer"; else echo "FAILED   answer: $out"; status=1; fi
out=$("$RIS" run test/ris/query.ri 2>&1)
if [ "$out" = 'PASS: read as Params reads, nothing on the heap' ]; then echo "runs     query"; else echo "FAILED   query: $out"; status=1; fi
out=$("$RIS" run test/ris/truncate.ri 2>&1)
if grep -qF "PASS: cut back and written over" <<<"$out" && grep -qF "truncate to 1 of 0 bytes" <<<"$out"; then echo "runs     truncate"; else echo "FAILED   truncate: $out"; status=1; fi

out=$("$RIS" run test/ris/json.ri 2>&1)
if [ "$out" = 'PASS: parsed, refused alike, written alike, on the tape' ]; then echo "runs     json"; else echo "FAILED   json: $out"; status=1; fi

out=$("$RIS" run test/ris/json_repeat.ri 2>&1)
if grep -qF 'nested keys are no repeat' <<<"$out" && grep -qF 'the key "k77" is written twice in one object' <<<"$out"; then echo "runs     json_repeat"; else echo "FAILED   json_repeat: $out"; status=1; fi

# Interpolation into puts or print is written on the tape, or on the heap
# when no tape runs; flat data is linked, saved as bytes and loaded back.
out=$("$RIS" run test/ris/interpolate.ri 2>&1)
if [ "$out" = $'on the tape: 42 -7 1.5 x true\nno newline tape\nitem 1\nitem 2\nends its line\nheap 3\nno tape when called 4\nthrough a var\nagain 1\nkept 2\nkept 2' ]; then echo "runs     interpolate"; else echo "FAILED   interpolate: $out"; status=1; fi
out=$("$RIS" run test/ris/flat.ri 2>&1)
if [ "$out" = $'16 bytes a node\n1 one\n2 two\n5 five\n8 eight\n9 nine\n25' ]; then echo "runs     flat"; else echo "FAILED   flat: $out"; status=1; fi
out=$("$RIS" run test/ris/link_check.ri 2>&1)
if grep -qF $'7' <<<"$out" && grep -qF "index 200 out of range for 1 elements" <<<"$out"; then echo "runs     link_check"; else echo "FAILED   link_check: $out"; status=1; fi
out=$("$RIS" run test/ris/loop_bounds.ri 2>&1)
if grep -qF '1 11 21 300' <<<"$out" && grep -qF "index -1 out of range for 3 elements" <<<"$out"; then echo "runs     loop_bounds"; else echo "FAILED   loop_bounds: $out"; status=1; fi
out=$("$RIS" run test/ris/refill_handoff.ri 2>&1)
if [ "$out" = '2 2 3 4' ]; then echo "runs     refill_handoff"; else echo "FAILED   refill_handoff: $out"; status=1; fi
out=$("$RIS" run test/ris/clear.ri 2>&1)
if [ "$out" = $'2 1 2\n3 2 3\n4 3 4\nxxxxend' ]; then echo "runs     clear"; else echo "FAILED   clear: $out"; status=1; fi
out=$(RIS_TAPE_STATS=1 "$RIS" run test/ris/side_warm.ri 2>&1)
if grep -qF '1000 scopes, 2 mappings made, 0 unmapped' <<<"$out" && grep -qF '1000 values moved' <<<"$out"; then echo "runs     side_warm"; else echo "FAILED   side_warm: $out"; status=1; fi
out=$("$RIS" run test/ris/side.ri 2>&1)
if [ "$out" = $'round 0: intact\nround 1: intact\nround 2: intact' ]; then echo "runs     side"; else echo "FAILED   side: $out"; status=1; fi
out=$("$RIS" run test/ris/scope_free.ri 2>&1)
if [ "$out" = $'round 99999\nwhile frees: true\nblock wrote 200000\nblock frees: true\nkept stays: true true\n123\ndef frees: true 5\nresult stays: true 42' ]; then echo "runs     scope_free"; else echo "FAILED   scope_free: $out"; status=1; fi
out=$("$RIS" run test/ris/scope_keep.ri 2>&1)
if [ "$out" = "50000 50000 9" ]; then echo "runs     scope_keep"; else echo "FAILED   scope_keep: $out"; status=1; fi
out=$("$RIS" run test/ris/in_place.ri 2>&1)
if [ "$out" = $'<li>item n0</li><li>item n1</li><li>item n2</li>\n<li>item n9</li>\nin place: true 1' ]; then echo "runs     in_place"; else echo "FAILED   in_place: $out"; status=1; fi
out=$("$RIS" run test/ris/array_api.ri 2>&1)
if grep -qF $'3 7 31 false\ntrue 2 \n2 true true\nDeploy is green\ntrue\n36 12\nHi all\n2 2 Hi all\n7 Morning!\n7 Ship it\n12 Deploy is green\n31 Hi all\nMorning!\n3, 7, 12, 31, 44\n3 6 31\n1 16 17 40 820\n31 3\n3 0 0\ntrue true true' <<<"$out" && grep -qF "first of an empty array" <<<"$out"; then echo "runs     array_api"; else echo "FAILED   array_api: $out"; status=1; fi
out=$("$RIS" run test/ris/index_view.ri 2>&1)
if grep -qF $'4 edges, last names 3, reads -1\nlevels 10 dist 1 2 4' <<<"$out" && grep -qF "index 9 out of range for 4 elements" <<<"$out"; then echo "runs     index_view"; else echo "FAILED   index_view: $out"; status=1; fi
out=$("$RIS" run test/ris/link_wide.ri 2>&1)
if grep -qF "link 255 does not fit 1 bytes" <<<"$out"; then echo "runs     link_wide"; else echo "FAILED   link_wide: $out"; status=1; fi

out=$("$RIS" run samples/ris/chat.ri 2>&1)
if [ "$(tail -3 <<<"$out")" = $'403 user 99 is not in the room\n400 bad request\nkept 3 messages' ] && grep -qF "200 alice: Ship it | bob: Deploy is green | alice: Morning! (users alice, bob, carol)" <<<"$out"; then echo "runs     samples/ris/chat"; else echo "FAILED   samples/ris/chat: $out"; status=1; fi
out=$("$RIS" run samples/ris/request.ri 2>&1)
if [ "$out" = $'200 OK Hello\n200 OK {"id":42,"name":"alice"}\n404 Not Found \n405 Method Not Allowed \n400 Bad Request' ]; then echo "runs     samples/ris/request"; else echo "FAILED   samples/ris/request: $out"; status=1; fi
# The web sample serves until killed: port 0, read back from its banner.
web=$(mktemp -d)
if ! command -v curl >/dev/null; then
  echo "skipped  samples/ris/web (no curl)"
elif "$RIS" build -o "$web/web" samples/ris/web.ri >/dev/null 2>&1; then
  "$web/web" 0 >"$web/log" 2>&1 &
  pid=$!
  url=""
  for _ in $(seq 50); do
    url=$(grep -o 'http://[^ ]*' "$web/log" 2>/dev/null) && break
    sleep 0.1
  done
  page=$(curl -s "$url")
  missing=$(curl -s -o /dev/null -w '%{http_code}' "${url%/1/status}/9/status")
  kill "$pid" 2>/dev/null
  if [ "$page" = $'<h1>alice</h1>\n<p class="status">Learning sequential memory management :-)</p>' ] && [ "$missing" = 404 ]; then echo "runs     samples/ris/web"; else echo "FAILED   samples/ris/web: $page $missing"; status=1; fi
else
  echo "FAILED   samples/ris/web: does not build"; status=1
fi
rm -rf "$web"
out=$("$RIS" run test/ris/to_heap.ri 2>&1)
if [ "$out" = $'GET /users\nGET,/users\n[3, 1, 2] [2, 3]\n/users 12' ]; then echo "runs     to_heap"; else echo "FAILED   to_heap: $out"; status=1; fi
out=$("$RIS" run test/ris/text_api.ri 2>&1)
if grep -qF $'3 12 true\ntrue false\n4 212\n/users/1\n4 true true\n-42 7 true\ntrue -2147483648\nShip it|7|it|7 Ship\ntrue\n1 5 11\n3 café false\n200 /users/1 took 12 ms\n200 /users/1 took 12 ms' <<<"$out" && grep -qF "not a number" <<<"$out"; then echo "runs     text_api"; else echo "FAILED   text_api: $out"; status=1; fi
out=$("$RIS" run test/ris/each_line.ri 2>&1)
if [ "$out" = $'[GET /][POST /users][][GET /a] 4\n[one] 1\n 0\n[b\r] 1' ]; then echo "runs     each_line"; else echo "FAILED   each_line: $out"; status=1; fi
out=$("$RIS" run samples/ris/report.ri 2>&1)
if [ "$out" = $'day 1: 4 hits, 1 errors, slow: /users/1/status (980 ms) /users/2 (640 ms)\nday 2: 3 hits, 0 errors, slow: /search (1210 ms)\nslowest each day: /users/1/status, /search' ]; then echo "runs     samples/ris/report"; else echo "FAILED   samples/ris/report: $out"; status=1; fi
out=$("$RIS" run samples/ris/hello.ri 2>&1)
if [ "$out" = $'Hello from ris, order 1\ntotal 1649' ]; then echo "runs     samples/ris/hello"; else echo "FAILED   samples/ris/hello: $out"; status=1; fi

# A JSON API's request path: the tape and the heap answer alike.
exe=$(mktemp)
if "$RIS" build --release -o "$exe" samples/ris/orders.ri >/dev/null 2>&1 && [ "$("$exe")" = "$("$exe" heap)" ] && [ "$("$exe" | tail -1)" = "16015853319686983776" ]; then
  echo "runs     samples/ris/orders (tape and heap alike)"
else
  echo "FAILED   samples/ris/orders"; status=1
fi
rm -f "$exe"

exe=$(mktemp)
if "$RIS" build --release -o "$exe" samples/ris/respond.ri >/dev/null 2>&1 && [ "$("$exe" | tail -1)" = "7480137599999527189" ]; then
  echo "runs     samples/ris/respond (checksum matches)"
else
  echo "FAILED   samples/ris/respond"; status=1
fi
rm -f "$exe"

# HPACK's tape overload agrees with the retained API across tape scopes.
out=$("$RIS" run --release test/ris/hpack.ri 2>&1)
if [ "$out" = \
  'PASS: tape HPACK fields, retained tables and malformed input' ]; then
  echo "runs     hpack"
else
  echo "FAILED   hpack: $out"
  status=1
fi


# Fixed-width fields, buffered tape lines, and integer text diagnostics.
out=$("$RIS" run test/ris/little_endian.ri 2>&1)
if [ "$out" = PASS ]; then
  echo "runs     little_endian"
else
  echo "FAILED   little_endian: $out"
  status=1
fi
out=$(python3 -c 'import sys
sys.stdout.write("the first line\n" + ("y" * 100 + "\n") * 20000)' |
  "$RIS" run test/ris/line_tape_keep.ri 2>&1)
if [ "$out" = PASS ]; then
  echo "runs     line_tape_keep"
else
  echo "FAILED   line_tape_keep: $out"
  status=1
fi
out=$(python3 -c 'import sys
sys.stdout.write("\n" + "x" * 20000 + "\r\n")
sys.stdout.write("hello\r\n" * 10000 + "tail\r")' |
  "$RIS" run test/ris/line_tape.ri 2>&1)
if [ "$out" = PASS ]; then
  echo "runs     line_tape"
else
  echo "FAILED   line_tape: $out"
  status=1
fi
out=$("$RIS" run test/ris/refill_default_init.ri 2>&1)
if [ "$out" = PASS ]; then
  echo "runs     refill_default_init"
else
  echo "FAILED   refill_default_init: $out"
  status=1
fi
out=$("$RIS" check test/ris/integer_text_floor.ri 2>&1)
if [ $? -ne 0 ]; then
  echo "FAILED   integer_text_floor: $out"
  status=1
fi
for name in le_array_read le_array_write le_string_read le_offset_overflow; do
  out=$("$RIS" run "test/ris/$name.ri" 2>&1)
  code=$?
  if [ "$code" -ne 0 ] &&
      grep -qF 'little-endian field out of range' <<<"$out"; then
    echo "refused  $name"
  else
    echo "FAILED   $name: $out"
    status=1
  fi
done

exit $status
