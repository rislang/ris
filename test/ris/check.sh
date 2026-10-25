#!/usr/bin/env bash
# ris's own checks: every program under test/ris/refused must be refused by
# the compiler with the expected message, test/ris/allowed.ri must compile
# and run, the fibers test must read back what each fiber wrote, a tape must
# grow past its first mapping in whole 64 KiB grains and refuse an index out
# of range, a Tre must step over subtrees, and the respond sample must
# print its known checksum. Fatal size errors must allocate nothing.
#
#   bash test/ris/check.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
RIS=${RIS:-./bin/ris}
status=0
# By default the blocks below run on every core (check_parallel.py).
if [ -z "${RIS_CHECK_SERIAL:-}" ]; then
  exec python3 test/ris/check_parallel.py
fi

# The heap workloads build every sample in release mode, the slowest gate:
# start them now beside the other checks and collect them at the end.
heap_log=$(mktemp)
python3 test/ris/heap_check.py >"$heap_log" 2>&1 &
heap_pid=$!

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

# Owner and pointer checking see the same callback through union dispatch.
out=$(
  graph_dir=$(mktemp -d)
  graph_probe="$graph_dir/call_graph_target.ri"
  for checker in owner pointer; do
    if [ "$checker" = owner ]; then
      operation='a = Workspace.new; b = a'
      needle='cannot copy or reassign an owner'
    else
      operation='text = Str.new("abc"); text.to_unsafe'
      needle='to_unsafe` of a Str outside a @[TapeUnsafe] def'
    fi
    sed "s/@OPERATION@/$operation/" test/ris/call_graph_target.ri.in \
      >"$graph_probe"
    result=$("$RIS" build --no-codegen "$graph_probe" 2>&1)
    if [ "$?" -ne 0 ] && grep -qF -- "$needle" <<<"$result"; then
      echo "refused  call_graph_target_$checker"
    else
      echo "FAILED   call_graph_target_$checker: $result"
    fi
  done
  rm -f "$graph_probe"
  rmdir "$graph_dir"
)
if [[ "$out" == *FAILED* ]]; then
  status=1
fi
printf '%s\n' "$out"

# Checked boundaries: opaque callbacks, module contracts and suspension.
out=$(python3 test/ris/call_contracts.py 2>&1)
if [ "$?" -eq 0 ]; then
  printf '%s\n' "$out"
else
  echo "FAILED   call_contracts: $out"
  status=1
fi

# A dead view permits refill; live views and pending operands forbid shrink.
for name in builder_clear builder_truncate builder_shift operand alias span \
    values_at link pop_optional element iterator pointer literal_operand \
    helper helper_two helper_generic dispatch callback helper_result \
    helper_recursive field_owner field_ontape callback_proc \
    callback_argument helper_self helper_named loop_clear loop_rebind loop_nested \
    loop_each loop_branch loop_until loop_backedge loop_array loop_chain \
    loop_entry loop_forever; do
  expect "shrink_$name" 'cannot shrink tape storage with a live view'
done
# Roots survive joins and holders; an emptied holder releases its view.
for name in holder nested_holder merged_view array_holder owner_holder \
    case_view or_view read_back holder_alias inexact_holder; do
  expect "shrink_$name" 'cannot shrink tape storage with a live view'
done
for name in branch_escape store_join return_owner; do
  expect "root_$name" 'cannot store a view beyond its owner scope'
done
out=$("$RIS" run test/ris/roots_holders.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'PASS: roots and holders' ]; then
  echo "runs     roots_holders"
else
  echo "FAILED   roots_holders: $out"
  status=1
fi

out=$("$RIS" run test/ris/shrink_refill.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'PASS: shrink refill' ]; then
  echo "runs     shrink_refill"
else
  echo "FAILED   shrink_refill: $out"
  status=1
fi

out=$("$RIS" run test/ris/shrink_read_helper.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'abc' ]; then
  echo "runs     shrink_read_helper"
else
  echo "FAILED   shrink_read_helper: $out"
  status=1
fi

out=$("$RIS" run test/ris/recursion_scratch.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'PASS: recursion scratch' ]; then
  echo "runs     recursion_scratch"
else
  echo "FAILED   recursion_scratch: $out"
  status=1
fi
out=$(
  for name in local mutual pending callback result view owner \
      callback_proc dispatch constructing consumed tree branch_pending \
      forwarded runtime_callback; do
    expect "recursion_$name" 'cannot recurse with growing tape'
  done
)
if [[ "$out" == *FAILED* ]]; then
  status=1
fi
printf '%s\n' "$out"

out=$("$RIS" run test/ris/yaml.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'PASS: yaml tape and heap APIs' ]; then
  echo "runs     yaml"
else
  echo "FAILED   yaml: $out"
  status=1
fi

out=$("$RIS" run test/ris/toml.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'PASS: toml tape and heap APIs' ]; then
  echo "runs     toml"
else
  echo "FAILED   toml: $out"
  status=1
fi

out=$("$RIS" run test/ris/time_tape_offset.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'PASS: time tape offsets' ]; then
  echo "runs     time_tape_offset"
else
  echo "FAILED   time_tape_offset: $out"
  status=1
fi

# B1 storage restrictions; B2 ordinary def and receiver borrows.
expect owner_temporary 'owner temporary requires a named declaration'
expect owner_inline 'owner temporary requires a named declaration'
expect owner_copy 'cannot copy or reassign an owner'
expect owner_reassign 'cannot copy or reassign an owner'
expect owner_field 'cannot store an owner in a field'
expect owner_class_field 'cannot store an owner in a field'
expect owner_ary 'cannot store an owner'
expect owner_array 'cannot store an owner'
expect owner_hash 'cannot store an owner'
expect owner_tuple 'cannot store an owner in a container, tuple or union'
expect owner_union 'cannot store an owner in a container, tuple or union'
expect owner_return 'cannot return an owner from a def'
expect owner_implicit_return 'cannot return an owner from a def'
for name in param explicit_param program explicit_program self local; do
  expect "owner_return_$name" \
    'cannot return an owner from a def; return a field view (Str/Ary) or take the owner as an argument'
done
expect owner_class 'requires a struct'
expect owner_copy 'borrow it: pass the owner variable'
expect owner_proc_argument 'owner arguments require a direct def call'
for name in self field alias typed_alias getter helper; do
  expect "owner_initialize_$name" \
    "cannot publish self or a field view from an owner's initialize"
done
out=$("$RIS" run test/ris/owners.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'PASS: owner fields' ]; then
  echo "runs     owners"
else
  echo "FAILED   owners: $out"
  status=1
fi

# Panics end the task; rescue cannot observe a half-built binding.
expect owner_construction_rescue 'iyi has no exceptions to rescue'
out=$(RIS_TAPE_STATS=1 "$RIS" run test/ris/owner_construction_panic.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qF 'PASS: owner construction panic cleanup' <<<"$out" &&
    [ "$(grep -cF 'iyi: panic: expected owner construction panic' <<<"$out")" -eq 100 ] &&
    ! grep -qF 'half-built owner became observable' <<<"$out" &&
    grep -qF '201 scopes, 103 mappings made, 100 unmapped' <<<"$out"; then
  echo "runs     owner_construction_panic (bounded scope cleanup)"
else
  echo "FAILED   owner_construction_panic: $out"
  status=1
fi

# -O0 construction copies a private temporary into local/program storage.
owner_ir=$(mktemp -d)
if "$RIS" build --emit llvm-ir -o "$owner_ir/owners" \
    test/ris/owners.ri >"$owner_ir/log" 2>&1 &&
    grep -qE '^define internal %Workspace .*Workspace::new' \
      "$owner_ir/owners.ll" &&
    grep -qE 'Workspace#initialize.*ptr %_' "$owner_ir/owners.ll" &&
    grep -qE 'store %Workspace .*ptr %workspace,' "$owner_ir/owners.ll" &&
    grep -qE 'store %Workspace .*ptr @ROOT,' "$owner_ir/owners.ll"; then
  echo "lowers   owners (private constructor copy)"
else
  echo "FAILED   owners (construction): $(cat "$owner_ir/log")"
  status=1
fi
rm -rf "$owner_ir"

expect heap_exemption \
  'runtime heap exemption is private'
expect string_parameter \
  'name : String is only read; take it as Str'
expect string_optional_parameter \
  'name : String? is only read; take it as Str?'
out=$("$RIS" run test/ris/string_parameters.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'PASS: retained String parameters' ]; then
  echo "runs     string_parameters"
else
  echo "FAILED   string_parameters: $out"
  status=1
fi

for name in text_parameter text_array text_capture \
            text_channel; do
  expect "$name" '.to_heap'
done
expect text_local_field \
  'name holds tape text; write the literal in place or keep it with .to_heap'
expect text_mixed_array 'to_heap'
expect text_mixed_hash 'to_heap'
expect text_literal_field '.to_heap'
expect text_interpolation_field '.to_heap'
expect text_interpolation_field \
  'make it an @[OnTape] struct with a Str field'
out=$("$RIS" run test/ris/text_default.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qF 'Str' <<<"$out" &&
    grep -qF 'PASS: default text' <<<"$out"; then
  echo "runs     text_default"
else
  echo "FAILED   text_default: $out"
  status=1
fi

out=$("$RIS" run test/ris/text_literal_heap.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qF 'PASS: literal heap places' <<<"$out"; then
  echo "runs     text_literal_heap"
else
  echo "FAILED   text_literal_heap: $out"
  status=1
fi

out=$("$RIS" run test/ris/borrowed_text.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qF 'PASS: borrowed std text' <<<"$out"; then
  echo "runs     borrowed_text"
else
  echo "FAILED   borrowed_text: $out"
  status=1
fi

expect class_field   "holds the tape type"
expect struct_field  "is a struct that is not @[OnTape]"
expect class_var     "copy it with .copy_to(Program.tape)"
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
expect outer_var '`to_heap` copies a Str or Ary'
expect owned_cache "to be String, not Str"

expect local_outer "is a variable of the code around this local_tape block"
expect local_mutate "cannot use outer tape value"
expect local_self 'cannot use outer tape value `self`'
expect local_return "cannot return a tape value"
expect local_break "cannot break a tape value"
expect local_yield_break "cannot break a tape value"
expect ffi_pointerof    "\`pointerof\` outside an @[Ffi] module"
expect ffi_pointer      "\`Pointer\` outside an @[Ffi] module"
expect ffi_to_unsafe    "Read a byte with \`s.byte_at(i)\`"
expect ffi_lib          "a \`lib\` block outside an @[Ffi] module"
expect ffi_string_new   "Build it with \`String.build(capacity)"
expect pointer_unsafe_reason "takes the reason the def needs a pointer"
expect pointer_unsafe_stray  "@[PointerUnsafe] marks a def"
expect pointer_unsafe_lib    "a \`lib\` block outside an @[Ffi] module"
expect raw_pointer      "to_unsafe\` of a Str outside a @[TapeUnsafe] def"
expect raw_view         "Str.new(pointer, size)\` outside a @[TapeUnsafe] def"
expect std/tape_unsafe_codec "reaches no \`lib\` fun or system call"
expect std/tape_unsafe_no_pointer "hands no tape pointer to the OS"
expect tape_pointer "\`unsafe_append\` outside a @[TapeUnsafe] def"
expect std/tape_pointer_codec "the pointer \`unsafe_append\` yields reaches no"
expect writer_grow      "private method 'grow' called for Str::Builder"
expect tree_entry       "private constant Tre::Entry(T) referenced"
expect array_grow       "private method 'grow' called for Ary(T)"
expect array_append     "append requires Ary(UInt8)"
expect heap_copy \
  "\`to_s\` of a Str outside a @[TapeToHeap] def copies"
expect heap_copy_top \
  "\`to_s\` of a Str outside a @[TapeToHeap] def"
expect heap_interpolation \
  "Interpolating a Str outside a @[TapeToHeap]"
expect heap_builder     "Writing a Str into a String::Builder"
expect refill           "\`@items\` is given a new Ary in \`take\`"
expect heap_copy        "tape -> heap -> tape pays this at every turn"
expect heap_memory      "Writing a Str into a String::Builder or"
expect heap_memory_print "Writing a Str into a Std::Io::Memory"
expect not_flat "Holder is not flat"
expect check_free "\`first\` is @[CheckFree], and this \`[]\` checks"
expect heap_escape_helper \
  "\`to_s\` of a Str outside a @[TapeToHeap] def copies"


for name in implicit fibers/implicit implicit_loop; do
  out=$(RIS_TAPE_STATS=1 "$RIS" run "test/ris/$name.ri" 2>&1)
  code=$?
  if [ "$code" -eq 0 ] && grep -qF 'PASS:' <<<"$out" &&
      { [ "$name" != implicit_loop ] ||
        grep -qF '1 scopes, 1 mappings made, 0 unmapped' <<<"$out"; }; then
    echo "runs     $name"
  else
    echo "FAILED   $name: $out"
    status=1
  fi
done

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
if [ "$?" = 3 ] && [ "$out" = $'flushed\ninner exit\nouter exit' ]; then
  echo "runs     cleanup_exit"
else
  echo "FAILED   cleanup_exit: $out"; status=1
fi

out=$("$RIS" run test/ris/zero_capacity.ri 2>&1)
if [ "$out" = $'123\n789\n456\nABC' ]; then echo "runs     zero_capacity"; else echo "FAILED   zero_capacity: $out"; status=1; fi

out=$("$RIS" run test/ris/scope_cleanup.ri 2>&1)
if [ "$out" = $'1\ntrue\ntrue\ntrue\nC\ntrue' ]; then echo "runs     scope_cleanup"; else echo "FAILED   scope_cleanup: $out"; status=1; fi

out=$("$RIS" run test/ris/lifetime_flow.ri 2>&1)
if [ "$out" = $'A\nA\nA\nA' ]; then echo "runs     lifetime_flow"; else echo "FAILED   lifetime_flow: $out"; status=1; fi

out=$("$RIS" run test/ris/pointer_unsafe.ri 2>&1)
if [ "$out" = 104 ]; then echo "runs     pointer_unsafe"; else echo "FAILED   pointer_unsafe: $out"; status=1; fi
for name in ffi pointer; do
  out=$("$RIS" build --no-codegen "test/ris/forbid/$name.ri" 2>&1)
  if grep -qF "manifest says \`forbid" <<<"$out"; then
    echo "refused  forbid/$name"
  else
    echo "FAILED   forbid/$name: $out"; status=1
  fi
done
out=$("$RIS" unsafe test/ris/forbid 2>&1)
if grep -qF "pointer.ri:2: @[PointerUnsafe] reads the first byte" <<<"$out" &&
   grep -qF "ffi.ri:1: @[Ffi]" <<<"$out"; then
  echo "lists    unsafe"
else
  echo "FAILED   unsafe: $out"; status=1
fi
out=$("$RIS" run test/ris/ffi_marked.ri 2>&1)
if [ "$out" = $'4\n111' ]; then echo "runs     ffi_marked"; else echo "FAILED   ffi_marked: $out"; status=1; fi

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

out=$("$RIS" run test/ris/array_append.ri 2>&1)
if [ "$out" = 'append: 104 bytes intact' ]; then echo "runs     array_append"; else echo "FAILED   array_append: $out"; status=1; fi

out=$("$RIS" run test/ris/grain.ri 2>&1)
if [ "$out" = 'PASS: tape mappings are whole 64 KiB grains' ]; then echo "runs     grain"; else echo "FAILED   grain: $out"; status=1; fi

out=$("$RIS" run test/ris/bounds.ri 2>&1)
if grep -qF $'10 25 35 35' <<<"$out" && grep -qF "index 3 out of range for 3 elements" <<<"$out"; then echo "runs     bounds"; else echo "FAILED   bounds: $out"; status=1; fi

out=$("$RIS" run test/ris/stream.ri 2>&1)
if grep -qF '7 1,2,5,6 3,4 0 7' <<<"$out" && grep -qF "Tre#close: 2 is not open" <<<"$out"; then echo "runs     stream"; else echo "FAILED   stream: $out"; status=1; fi

out=$("$RIS" run test/ris/owned.ri 2>&1)
if [ "$out" = 'PASS: explicit owned copy, typed cache boundary, UTF-8, empty text and scope reuse' ]; then echo "runs     owned"; else echo "FAILED   owned: $out"; status=1; fi

out=$("$RIS" run test/ris/writer.ri 2>&1)
if [ "$out" = '0 -42 9223372036854775807 -9223372036854775808 a&amp;b&lt;c&gt;&quot;d&#39;e <b>' ]; then echo "runs     writer"; else echo "FAILED   writer: $out"; status=1; fi

# Two pieces, String or on the tape, go out in one socket write.
out=$("$RIS" run test/ris/tape_primitives.ri 2>&1)
if [ "$out" = 'PASS: write_bytes, shift and Str::Scanner' ]; then echo "runs     tape_primitives"; else echo "FAILED   tape_primitives: $out"; status=1; fi
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

# Interpolation is tape text in every ris scope; flat data is linked,
# saved as bytes and loaded back.
out=$("$RIS" run test/ris/interpolate.ri 2>&1)
if [ "$out" = $'on the tape: 42 -7 1.5 x true\nno newline tape\nitem 1\nitem 2\nends its line\nheap 3\nno tape when called 4\nthrough a var\nagain 1\nkept 2\nkept 2' ]; then echo "runs     interpolate"; else echo "FAILED   interpolate: $out"; status=1; fi
out=$("$RIS" run test/ris/flat.ri 2>&1)
if [ "$out" = $'16 bytes a node\n1 one\n2 two\n5 five\n8 eight\n9 nine\n25' ]; then echo "runs     flat"; else echo "FAILED   flat: $out"; status=1; fi
out=$("$RIS" run test/ris/link_check.ri 2>&1)
if grep -qF $'7' <<<"$out" && grep -qF "index 200 out of range for 1 elements" <<<"$out"; then echo "runs     link_check"; else echo "FAILED   link_check: $out"; status=1; fi
out=$("$RIS" run test/ris/loop_bounds.ri 2>&1)
if grep -qF '1 11 21 300 3' <<<"$out" && grep -qF "index -1 out of range for 3 elements" <<<"$out"; then echo "runs     loop_bounds"; else echo "FAILED   loop_bounds: $out"; status=1; fi
# Shrinking directly, through an argument/holder, or in the condition
# must retain checks; CheckFree verifies safe indexing still lowers.
for mode in clear store pop 'pop?' argument holder condition if words \
    cached truncate shift word_truncate yield operator; do
  out=$("$RIS" run test/ris/loop_shrink.ri -- "$mode" 2>&1)
  code=$?
  if [ "$code" -ne 0 ] &&
      { grep -qF 'index 0 out of range for 0 elements' <<<"$out" ||
        grep -qF 'little-endian field out of range' <<<"$out" ||
        grep -qF 'index 0 out of range for 0 bytes' <<<"$out"; }; then
    echo "runs     loop_shrink ($mode)"
  else
    echo "FAILED   loop_shrink ($mode): $out"
    status=1
  fi
done
out=$("$RIS" run test/ris/loop_shrink.ri -- safe 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = $'42\n4050765991979987505' ]; then
  echo "runs     loop_shrink (safe CheckFree reads)"
else
  echo "FAILED   loop_shrink (safe): $out"
  status=1
fi

# CheckFree checks []/[]=; inspect IR to prove word reads lower too.
loops=$(mktemp -d)
if "$RIS" build --emit llvm-ir -o "$loops/loops" \
    test/ris/loop_shrink.ri >"$loops/log" 2>&1 &&
    grep -qF '__loop_read_bytes_at' "$loops/loops.ll"; then
  echo "lowers   loop_shrink (safe word reads)"
else
  echo "FAILED   loop_shrink (word lowering): $(cat "$loops/log")"
  status=1
fi
rm -rf "$loops"

out=$("$RIS" run test/ris/loop_words.ri 2>&1)
if grep -qF '8101531983959975010 true false false' <<<"$out" && grep -qF "little-endian field out of range" <<<"$out"; then echo "runs     loop_words"; else echo "FAILED   loop_words: $out"; status=1; fi
out=$("$RIS" run test/ris/scanner_cursor.ri 2>&1)
if [ "$out" = '6 5 -1 12 208' ]; then echo "runs     scanner_cursor"; else echo "FAILED   scanner_cursor: $out"; status=1; fi
out=$("$RIS" run test/ris/loop_size_twice.ri 2>&1)
if grep -qF "index 2 out of range for 2 bytes" <<<"$out"; then echo "runs     loop_size_twice"; else echo "FAILED   loop_size_twice: $out"; status=1; fi
out=$("$RIS" run test/ris/refill_handoff.ri 2>&1)
if [ "$out" = '2 2 3 4' ]; then echo "runs     refill_handoff"; else echo "FAILED   refill_handoff: $out"; status=1; fi
out=$("$RIS" run test/ris/clear.ri 2>&1)
if [ "$out" = $'2 1 2\n3 2 3\n4 3 4\nxxxxend' ]; then echo "runs     clear"; else echo "FAILED   clear: $out"; status=1; fi
out=$(RIS_TAPE_STATS=1 "$RIS" run test/ris/side_warm.ri 2>&1)
if grep -qF '1001 scopes, 3 mappings made, 0 unmapped' <<<"$out" && grep -qF '1000 side regions' <<<"$out"; then echo "runs     side_warm"; else echo "FAILED   side_warm: $out"; status=1; fi
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

out=$("$RIS" run test/ris/string_arguments.ri 2>&1)
if [ "$out" = 'PASS: String arguments borrow without allocation' ]; then
  echo "runs     string_arguments"
else
  echo "FAILED   string_arguments: $out"; status=1
fi

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

# A lexer that steps its own offset through tape text is warned, not
# refused; the same lexer on Str::Scanner is not.
out=$("$RIS" check test/ris/warned/scanner_hint.ri 2>&1)
if [ $? -eq 0 ] && grep -qF '`@pos` walks tape text by hand' <<<"$out"; then
  echo "warned   scanner_hint"
else
  echo "FAILED   scanner_hint: $out"
  status=1
fi
out=$("$RIS" run test/ris/scanner_words.ri 2>&1)
if [ "$out" = 2 ]; then
  echo "runs     scanner_words"
else
  echo "FAILED   scanner_words: $out"
  status=1
fi

out=$("$RIS" run test/ris/signal_flags.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = $'true\ntrue' ]; then
  echo "runs     signal_flags"
else
  echo "FAILED   signal_flags: $out"; status=1
fi
out=$("$RIS" run test/ris/cleanup_self.ri 2>/dev/null)
if [ "$?" -eq 0 ] && [ "$out" = $'0\n9\n6' ]; then
  echo "runs     cleanup_self"
else
  echo "FAILED   cleanup_self: $out"; status=1
fi
out=$("$RIS" run test/ris/cleanup_cancel.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = $'9\ncancel alive\ncancel done' ]; then
  echo "runs     cleanup_cancel"
else
  echo "FAILED   cleanup_cancel: $out"; status=1
fi
out=$("$RIS" run --no-gc test/ris/fault_no_heap.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'fault path: zero heap' ]; then
  echo "runs     fault_no_heap (--no-gc)"
else
  echo "FAILED   fault_no_heap: $out"; status=1
fi
out=$("$RIS" run test/ris/cleanup_current.ri 2>/dev/null)
if [ "$?" -eq 0 ] && [ "$out" = $'2\n4\n5\n7\nalive' ]; then
  echo "runs     cleanup_current"
else
  echo "FAILED   cleanup_current: $out"; status=1
fi
out=$("$RIS" run --no-gc test/ris/task_limit.ri 2>&1)
if [ "$?" -eq 1 ] &&
    [ "$out" = 'ris: fatal: group task limit 2147483647 reached' ]; then
  echo "fatal    task_limit (--no-gc)"
else
  echo "FAILED   task_limit: $out"; status=1
fi
out=$("$RIS" run --no-gc test/ris/unwind_no_heap.ri 2>&1)
if [ "$?" -eq 1 ] &&
    [ "$out" = 'ris: fatal: raise during cleanup unwinding' ]; then
  echo "fatal    unwind_no_heap (--no-gc)"
else
  echo "FAILED   unwind_no_heap: $out"; status=1
fi
out=$("$RIS" run test/ris/unwind_failure.ri 2>&1)
if [ "$?" -ne 0 ] &&
    grep -qF 'ris: fatal: raise during cleanup unwinding' <<<"$out" &&
    ! grep -qF 'must not run' <<<"$out"; then
  echo "fatal    unwind_failure"
else
  echo "FAILED   unwind_failure: $out"; status=1
fi

# Reserved side growth keeps addresses and uses bounded mappings.
out=$(RIS_TAPE_STATS=1 "$RIS" run --no-gc test/ris/stable_growth.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qF 'PASS: stable interleaved growth' <<<"$out" &&
    grep -qF '0 growth moves' <<<"$out" &&
    grep -qF '4 mappings made' <<<"$out" &&
    grep -qF '2 side regions' <<<"$out"; then
  echo "runs     stable_growth (--no-gc, bounded mappings)"
else
  echo "FAILED   stable_growth: $out"; status=1
fi
out=$("$RIS" run --no-gc test/ris/side_overflow.ri 2>&1)
if [ "$?" -eq 1 ] &&
    [ "$out" = 'iyi: tape side reservation exhausted: 1073741825' ]; then
  echo "fatal    side_overflow (--no-gc)"
else
  echo "FAILED   side_overflow: $out"; status=1
fi

# Fatal size errors exit directly, with exact diagnostics and no heap.
if ! python3 test/ris/size_failure.py; then
  status=1
fi

# Census, runtime budgets and the collector-free trap share one gate.
# Audit categories are separate from potential allocation-site totals.
for pair in 'heap_migration migration' 'heap_opaque opaque' \
            'heap_exemptions exemption'; do
  read -r name category <<<"$pair"
  out=$("$RIS" heap --user "test/ris/$name.ri" 2>&1)
  if [ $? -eq 0 ] && grep -qE "^$category: [1-9][0-9]*$" <<<"$out"; then
    echo "census   $name ($category)"
  else
    echo "FAILED   $name: $out"
    status=1
  fi
done
out=$("$RIS" heap --user test/ris/heap_migration.ri 2>&1)
for mark in 'to_heap:' 'to_s to String:' '@[TapeToHeap]:' 'String API:'; do
  if ! grep -qF "$mark" <<<"$out"; then
    echo "FAILED   heap_migration: missing $mark"
    status=1
  fi
done
out=$("$RIS" heap --user test/ris/heap_opaque.ri 2>&1)
for mark in 'proc call:' 'virtual targets (all traversed):' 'FFI:'; do
  if ! grep -qF "$mark" <<<"$out"; then
    echo "FAILED   heap_opaque: missing $mark"
    status=1
  fi
done
if ! python3 test/ris/heap_check_test.py; then
  status=1
fi
out=$(RIS_HEAP_STATS=1 "$RIS" run --no-gc test/ris/heap_zero.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qF 'zero42' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     heap_zero (--no-gc)"
else
  echo "FAILED   heap_zero: $out"
  status=1
fi
out=$("$RIS" run --no-gc test/ris/heap_class.ri 2>&1)
if [ "$?" -ne 0 ] &&
    grep -qF 'ris: heap allocation with --no-gc:' <<<"$out"; then
  echo "refused  heap_class (--no-gc trap)"
else
  echo "FAILED   heap_class: $out"
  status=1
fi
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/heap_allocator.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qF 'ris heap: 1 allocations, 7 bytes' <<<"$out"; then
  echo "counts   heap_allocator (direct ABI)"
else
  echo "FAILED   heap_allocator: $out"
  status=1
fi
out=$("$RIS" run --no-gc test/ris/heap_allocator.ri 2>&1)
if [ "$?" -ne 0 ] &&
    grep -qF 'ris: heap allocation with --no-gc: 7 bytes' <<<"$out"; then
  echo "refused  heap_allocator (--no-gc trap)"
else
  echo "FAILED   heap_allocator trap: $out"
  status=1
fi
out=$(RIS_HEAP_STATS=1 "$RIS" run --no-gc test/ris/heap_fibers.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qF 'fiber42' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     heap_fibers (--no-gc runtime bookkeeping)"
else
  echo "FAILED   heap_fibers: $out"
  status=1
fi
out=$("$RIS" heap --user test/ris/heap_fiber_capture.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qF 'closure: 1' <<<"$out"; then
  echo "census   heap_fiber_capture (user capture retained)"
else
  echo "FAILED   heap_fiber_capture: $out"
  status=1
fi
out=$("$RIS" run --no-gc test/ris/heap_fiber_capture.ri 2>&1)
if [ "$?" -ne 0 ] &&
    grep -qF 'ris: heap allocation with --no-gc:' <<<"$out"; then
  echo "refused  heap_fiber_capture (--no-gc trap)"
else
  echo "FAILED   heap_fiber_capture trap: $out"
  status=1
fi
for name in heap_handles heap_io; do
  out=$("$RIS" run --no-gc "test/ris/$name.ri" 2>&1)
  if [ "$?" -ne 0 ] &&
      grep -qF 'ris: heap allocation with --no-gc:' <<<"$out"; then
    echo "refused  $name (program value, not runtime metadata)"
  else
    echo "FAILED   $name: $out"
    status=1
  fi
done
out=$("$RIS" heap --user test/ris/heap_fields.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qF 'class: 1' <<<"$out" &&
    grep -qF 'array: 1' <<<"$out"; then
  echo "census   heap_fields (instance initializer reached)"
else
  echo "FAILED   heap_fields: $out"
  status=1
fi
out=$("$RIS" heap --user test/ris/heap_kinds.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qF 'class: 1' <<<"$out" &&
    grep -qF 'string: 1' <<<"$out" && grep -qF 'array: 1' <<<"$out" &&
    grep -qF 'hash: 2' <<<"$out" && grep -qF 'closure: 1' <<<"$out"; then
  echo "census   heap_kinds (unused def omitted)"
else
  echo "FAILED   heap_kinds: $out"
  status=1
fi

for name in program_alias program_helper program_local_init \
    program_nested_alias program_loop_alias; do
  expect "$name" 'copy it with .copy_to(Program.tape)'
done
expect program_copy_forged 'program initializer is private'
expect program_threads 'program tape writes require a single kernel thread'
expect program_field_thread \
  'program tape writes require a single kernel thread'
for name in program_tape program_growth; do
  out=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 \
    "$RIS" run --no-gc "test/ris/$name.ri" 2>&1)
  if [ "$?" -eq 0 ] && grep -qF 'PASS: program' <<<"$out" &&
      grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
    echo "runs     $name (--no-gc)"
  else
    echo "FAILED   $name: $out"
    status=1
  fi
done
mappings=$(sed -n \
  's/^ris tape:.*scopes, \([0-9]*\) mappings made.*/\1/p' <<<"$out")
if [ -n "$mappings" ] && [ "$mappings" -le 8 ]; then
  echo "bounded  program growth ($mappings mappings for 10,000 calls)"
else
  echo "FAILED   program growth mappings: $out"
  status=1
fi
out=$("$RIS" run test/ris/program_readers.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'PASS: program tape readers' ]; then
  echo "runs     program_readers (kernel threads)"
else
  echo "FAILED   program_readers: $out"
  status=1
fi
out=$("$RIS" run test/ris/program_text.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'value 42' ]; then
  echo "runs     program text constant"
else
  echo "FAILED   program text constant: $out"
  status=1
fi

wait "$heap_pid" || status=1
cat "$heap_log"
rm -f "$heap_log"

if [ "$status" -eq 0 ]; then
  echo "PASS: all ris checks"
else
  echo "FAIL: ris checks"
fi
exit $status
