#!/usr/bin/env bash
# ris's own checks: every program under test/ris/refused must be refused by
# the compiler with the expected message, test/ris/allowed.ri must compile
# and run, the fibers test must read back what each fiber wrote, a tape must
# grow past its first mapping in whole 64 KiB grains and refuse an index out
# of range, a RisTree must step over subtrees, and the respond sample must
# print its known checksum. Fatal size errors must allocate nothing.
#
#   bash test/ris/check.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
RIS=${RIS:-./bin/ris}
status=0
# By default the blocks below run on every core (check_parallel.py).
if [ -z "${RIS_CHECK_SERIAL:-}" ]; then
  python3 test/ris/check_parallel.py; rc=$?
  bash scripts/kill-tests.sh
  exit $rc
fi

# Migration APIs remain checked, but executing them must trap with a site.
heap_trap() {
  local name=$1 out code
  out=$("$RIS" run "test/ris/$name.ri" 2>&1); code=$?
  if [ "$code" -ne 0 ] &&
      grep -qF 'ris: heap allocation:' <<<"$out" &&
      grep -qE '  at .*:[0-9]+:[0-9]+' <<<"$out"; then
    echo "traps    $name (heap migration, source site)"
  elif [ "$code" -ne 0 ] && grep -qF 'Error:' <<<"$out" &&
      grep -qE 'String|Array|Hash|tape' <<<"$out"; then
    # A program's literals and to_s are tape values now: the heap path is
    # refused at compile time, before it can trap.
    echo "refused  $name (heap migration, at compile time)"
  elif [ "$code" -eq 0 ]; then
    # A program's Array, Hash and text are tape types now: no heap left.
    echo "runs     $name (heap migration now on the tape)"
  else
    echo "FAILED   $name: expected heap trap with source site: $out"
    status=1
  fi
} # heap_trap

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

# Empty local collections fix their types at the first store.
out=$("$RIS" run test/ris/array_infer.ri 2>&1)
if [ "$?" -eq 0 ] &&
    [ "$out" = 'PASS: first-store array and hash inference' ]; then
  echo 'runs     array_infer'
else
  echo "FAILED   array_infer: $out"; status=1
fi
expect array_infer_mismatch '[] of T'
expect array_infer_read '[] of ElementType'
expect array_infer_none '[] of ElementType'
expect array_infer_field '[] of ElementType'
expect array_infer_default '[] of ElementType'
expect array_infer_constant '[] of ElementType'
expect hash_infer_key '{} of K => V'
expect hash_infer_value '{} of K => V'
expect hash_infer_field '{} of KeyType => ValueType'
expect hash_infer_read '{} of KeyType => ValueType'
expect hash_infer_none '{} of KeyType => ValueType'
expect hash_infer_default_key '{} of K => V'
expect hash_infer_default_value '{} of K => V'

expect array_infer_branch_mismatch '[] of T'
expect array_infer_concat_mismatch '[] of T'
expect hash_infer_default_field '{} of KeyType => ValueType'
expect hash_infer_default_read '{} of KeyType => ValueType'
expect hash_infer_default_parameter '{} of KeyType => ValueType'

# Workers consume in-band quits and fail bounded posts without spinning.
out=$(RIS="$RIS" python3 test/ris/workers_check.py 2>&1)
if [ "$?" -eq 0 ]; then
  printf '%s\n' "$out"
else
  echo "FAILED   workers sample: $out"; status=1
fi

# Reflection must not expose unrelated private declarations.
expect reflection_private 'does not export'

# Runtime storage has no application API.
expect message_storage_private 'undefined constant RisMessagePool'

# The board core owns typed queues independently of tasks and groups.
out=$(RIS="$RIS" bash test/ris/board_checks.sh 2>&1)
if [ "$?" -eq 0 ]; then
  printf '%s\n' "$out"
else
  echo "FAILED   board core checks: $out"; status=1
fi

expect board_union 'use a nominal struct with a union field'
expect board_cancelled 'wrap that data in a nominal message struct'
expect board_pointer 'NamedTuple(value: Pointer(Int32))'
expect board_class_limit 'send String, Array bytes or a value struct'
expect board_class_post 'send String, Array bytes or a value struct'
expect board_link 'use Array nodes with checked integer indices'
expect board_recursive 'use RisTree or Array nodes with checked integer indices'
expect board_closure 'send String, Array bytes or a value struct'
expect board_owner 'send String, Array bytes or a value struct'

# Tasks capture Share values, or take a value handed off (TAPE_SPEC 5.1).
expect task_capture_mutable 'build tape values inside the spawn'
expect task_capture_assigned 'a mutable borrow across tasks'
expect task_handoff_reused 'the task owns it now'
expect select_gone 'ris has no select'
expect channel_gone 'undefined constant Channel'

# Timed joins broadcast completion without cancelling the retained task.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/task_wait.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qxF 'PASS: task waits' <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     task_wait (broadcast, deadlines, cancel, panic)"
else
  echo "FAILED   task_wait: $out"; status=1
fi

# Task, fiber, group and defer slots are pooled: 100,000 tasks in rounds
# take program storage in the first round only; stale handles refused.
out=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 "$RIS" run test/ris/task_reuse.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qxF 'PASS: task reuse' <<<"$out" &&
    grep -qxF 'program storage after the first round: steady' <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out" &&
    grep -q '^ris program storage: [0-9]* bytes taken$' <<<"$out"; then
  echo "runs     task_reuse (100,000 tasks, steady program storage)"
else
  echo "FAILED   task_reuse: $(grep -v '^ris tape\|  at \|round panic' <<<"$out")"
  status=1
fi

# Interpolated output and panic text from iyi library code stay on tape.
out=$(
  probe=$(mktemp -d)
  "$RIS" build -o "$probe/retained" \
    test/ris/refused/interpolation_retained.ri 2>&1
  code=$?
  rm -rf "$probe"
  exit "$code"
)
if [ "$?" -ne 0 ] &&
    grep -qE 'use String.interpolate\(...\) on the current tape|retain it with `.copy_to' <<<"$out"; then
  echo 'refused  interpolation_retained (names the String form)'
else
  echo "FAILED   interpolation_retained: $out"; status=1
fi
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/interpolation_sinks.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qxF 'PASS: interpolation sinks' <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo 'runs     interpolation_sinks (library output, String argument, panic)'
else
  echo "FAILED   interpolation_sinks: $out"; status=1
fi

# Autocert broadcasts cache results with independent waiter deadlines.
out=$(RIS="$RIS" python3 test/ris/autocert_checks.py 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qF 'PASS: autocert cancellation' <<<"$out"; then
  printf '%s\n' "$out"
else
  echo "FAILED   autocert lifecycle: $out"; status=1
fi

# Config and name/stop variants pass the Copyable codec without heap IO.
out=$(RIS_HEAP_STATS=1 "$RIS" run \
  test/ris/autocert_wire.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qxF 'PASS: autocert Copyable config, bounded orders and stop' \
      <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo 'runs     autocert_wire (no GC, zero heap, config, orders, stop)'
else
  echo "FAILED   autocert wire: $out"; status=1
fi

# Joining waits for cleanup and refuses later adoption.
out=$(RIS_HEAP_STATS=1 "$RIS" run \
  test/ris/group_lifecycle.ri 2>&1)
if [ "$?" -ne 0 ] &&
    grep -qxF 'PASS: group lifecycle' <<<"$out" &&
    grep -qF 'the group has ended' <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     group_lifecycle (no GC, zero heap, ended refusal)"
else
  echo "FAILED   group_lifecycle: $out"; status=1
fi

# A task answers tape values; the reader gets its own copy. Zero heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/task_tape_result.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = $'<42>\n60\n7\nONE\n5\nslow\n<ok>\nris heap: 0 allocations, 0 bytes' ]; then
  echo "runs     task_tape_result (String, Array, Hash and tuple values, zero heap)"
else
  echo "FAILED   task_tape_result: $out"; status=1
fi
# A task answers an @[OnTape] struct and nested containers. Zero heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/task_value_shapes.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = $'card7\n6\nc2\n3\nx1\n0\nz3\n3\n0\n5\nris heap: 0 allocations, 0 bytes' ]; then
  echo "runs     task_value_shapes (OnTape struct, nested containers, zero heap)"
else
  echo "FAILED   task_value_shapes: $out"; status=1
fi

# Everyday String/Array/Hash calls in a program stay on the tape.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/core_api.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qxF 'HELLO, WORLD' <<<"$out" &&
    grep -qxF '00042' <<<"$out" && grep -qxF '78' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     core_api (String, Array and Hash surface, zero heap)"
else
  echo "FAILED   core_api: $out"; status=1
fi

for name in string_api array_api hash_api; do
  out=$(RIS_HEAP_STATS=1 "$RIS" run "test/ris/$name.ri" 2>&1)
  if [ "$?" -eq 0 ] && grep -qxF "PASS: $name" <<<"$out" &&
      grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
    echo "runs     $name (zero heap)"
  else
    echo "FAILED   $name: $out"; status=1
  fi
done

# No raw allocator bypasses the typed owner model.
expect heap_pointer 'General allocation is unavailable'

# Std foundations retain state in typed runs and expose tape error text.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/std_foundations.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qF 'std foundations ok' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     std_foundations (typed owner and error text, zero heap)"
else
  echo "FAILED   std_foundations: $out"; status=1
fi

# Bulk tape/local copies check spans and preserve indexed view order.
result=$("$RIS" build test/ris/tape_local_copy.ri -o /tmp/ris-local-copy-$$ 2>&1)
if [ "$?" -eq 0 ]; then
  result=$(/tmp/ris-local-copy-$$ 2>&1)
  if [ "$?" -eq 0 ] && [ "$result" = 'PASS: checked local copies' ]; then
    echo 'runs     tape_local_copy'
  else
    echo "FAILED   tape_local_copy: $result"; status=1
  fi
  for kind in text array store view; do
    result=$(/tmp/ris-local-copy-$$ "$kind" 2>&1)
    if [ "$?" -ne 0 ] && grep -qF 'local copy out of range' <<<"$result"; then
      echo "refused  tape_local_copy $kind range"
    else
      echo "FAILED   tape_local_copy $kind: $result"; status=1
    fi
  done
  rm -f /tmp/ris-local-copy-$$
else
  echo "FAILED   tape_local_copy build: $result"; status=1
fi

# A pipe's writer waits while the pipe is full (930722c made it panic).
out=$("$RIS" run test/ris/pipe_wait.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qxF 'PASS: pipe writer waits' <<<"$out"; then
  echo "runs     pipe_wait (OS pipe: writer waits, order, closed reader)"
else
  echo "FAILED   pipe_wait: $out"; status=1
fi

# Memory streams, reader wrappers and byte formats stay on the tape.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/std_io_tape.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qxF 'stdio tape ok' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     std_io_tape (zero heap)"
else
  echo "FAILED   std_io_tape: $out"; status=1
fi

# Metadata paths, IDs and missing-file diagnostics stay on tape.
out=$(RIS="$RIS" bash test/ris/file_metadata.sh 2>&1)
if [ "$?" -eq 0 ]; then
  echo "runs     file_metadata (no GC, zero heap, missing paths)"
else
  echo "FAILED   file_metadata: $out"; status=1
fi

# Importing math and using its tables must never allocate on the heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/math_no_heap.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qxF 'PASS: math constants and functions, zero heap' <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     math_no_heap (no GC, exact result bits)"
else
  echo "FAILED   math_no_heap: $out"; status=1
fi

# Decimal conversion includes exact rounding and must stay off the heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run \
  test/ris/float_parse_no_heap.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qxF 'PASS: float parsing, zero heap' <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     float_parse_no_heap (no GC, exact result bits)"
else
  echo "FAILED   float_parse_no_heap: $out"; status=1
fi

# Typed runs reuse, merge, relocate and retain typed stale views.
out=$("$RIS" run test/ris/slice_pool.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'PASS: SlicePool' ]; then
  echo "runs     slice_pool"
else
  echo "FAILED   slice_pool: $out"; status=1
fi

# SlicePool failures are fatal checked errors, including without the GC.
out=$(
  exe=$(mktemp)
  if "$RIS" build test/ris/slice_pool_errors.ri -o "$exe"; then
    for mode in negative overflow foreign foreign_realloc bounds slice \
      negative_realloc realloc_overflow constructor run_negative_offset \
      run_negative_size run_overflow run_past_end borrowed_foreign; do
      result=$("$exe" "$mode" 2>&1)
      code=$?
      case "$mode" in
        negative|negative_realloc|constructor) expected='iyi: tape bad size: -1' ;;
        overflow|realloc_overflow)
          expected='iyi: tape size overflow: 9223372036854775807 * 4' ;;
        foreign|foreign_realloc|borrowed_foreign)
          expected='iyi: SlicePool foreign or invalid run: 0' ;;
        bounds) expected='iyi: SlicePool index out of bounds: 2' ;;
        slice|run_negative_offset|run_negative_size|run_overflow|run_past_end)
          expected='iyi: SlicePool slice out of bounds: 0' ;;
      esac
      if [ "$code" -eq 1 ] && [ "$result" = "$expected" ]; then
        echo "fatal    slice_pool_$mode"
      else
        echo "FAILED   slice_pool_$mode: $result"
      fi
    done
  else
    echo "FAILED   slice_pool_errors build"
  fi
  rm -f "$exe"
)
if [[ "$out" == *FAILED* ]]; then status=1; fi
printf '%s\n' "$out"

expect slice_pool_links 'realloc_slice refuses self-relative links'
# Nested arrays are pooled handles, including hash values.
for name in nested_containers long_lived_containers static_array_copy \
    big_tape mime path std_text_tape; do
  out=$(RIS_HEAP_STATS=1 "$RIS" run "test/ris/$name.ri" 2>&1)
  if [ "$?" -eq 0 ] && grep -qF 'PASS:' <<<"$out" &&
      grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
    echo "runs     $name (zero heap)"
  else
    echo "FAILED   $name: $out"; status=1
  fi
done
for name in nested_run_view nested_run_helper_view program_run_view \
    hash_run_view nested_run_field_view; do
  expect "$name" 'cannot grow a pool run with a live view'
done
expect nested_run_overwrite 'cannot shrink tape storage with a live view'
expect growing_tree 'use SlicePool(T)'
expect growing_field 'use SlicePool(T)'
expect growing_owner 'cannot store an owner in a container'
expect growing_union 'use SlicePool(T)'
expect growing_recursive 'use SlicePool(T)'
expect shrink_element 'use SlicePool(T)'

# Owner and pointer checking see the same callback through union dispatch.
out=$(
  graph_dir=$(mktemp -d)
  graph_probe="$graph_dir/call_graph_target.ri"
  for checker in owner pointer; do
    if [ "$checker" = owner ]; then
      operation='a = Workspace.new; b = a'
      needle='cannot copy or reassign an owner'
    else
      operation='text = String.new("abc"); text.to_unsafe'
      needle='to_unsafe` of a String outside a @[TapeUnsafe] def'
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

# Tape type annotations survive module artifacts.
result=$(python3 test/ris/iyimod_tape.py 2>&1)
if [ "$?" -eq 0 ]; then
  printf '%s\n' "$result"
else
  echo "FAILED   iyimod_tape: $result"
  status=1
fi

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
    values_at link pop_optional iterator pointer literal_operand \
    helper helper_two helper_generic dispatch callback helper_result \
    helper_recursive field_owner field_ontape callback_proc \
    callback_argument helper_self helper_named loop_clear loop_rebind loop_nested \
    loop_each loop_branch loop_until loop_backedge loop_array loop_chain \
    loop_entry loop_forever pool_run pool_run_pop pool_run_helper; do
  expect "shrink_$name" 'cannot shrink tape storage with a live view'
done
# Roots survive joins and holders; an emptied holder releases its view.
for name in holder nested_holder merged_view array_holder owner_holder \
    case_view or_view read_back holder_alias inexact_holder deep_fields; do
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

heap_trap yaml

heap_trap toml

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
    'cannot return an owner from a def; return a field view (String/Array) or take the owner as an argument'
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
# Retained panic text adds one program-owned tape mapping and scope.
expect owner_construction_rescue 'iyi has no exceptions to rescue'
out=$(RIS_TAPE_STATS=1 "$RIS" run test/ris/owner_construction_panic.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qF 'PASS: owner construction panic cleanup' <<<"$out" &&
    [ "$(grep -cF 'iyi: panic: expected owner construction panic' <<<"$out")" -eq 100 ] &&
    ! grep -qF 'half-built owner became observable' <<<"$out" &&
    grep -qF '202 scopes, 6 mappings made, 0 unmapped' <<<"$out"; then
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

# Deep copies preserve concrete and inherited fields, splitting sharing.
out=$("$RIS" run test/ris/class_copy.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'PASS: class copies' ]; then
  echo "runs     class_copy"
else
  echo "FAILED   class_copy: $out"
  status=1
fi
# Copy jobs use scratch storage; depth never consumes the native stack.
# Keep build and execution together when check_parallel.py splits blocks.
out=$(
  copy_dir=$(mktemp -d)
  if "$RIS" build test/ris/copy_deep.ri -o "$copy_dir/deep" &&
      (ulimit -s 1024; "$copy_dir/deep"); then
    echo 'PASS: bounded copy stack'
  else
    echo 'FAILED: bounded copy stack'
  fi
  rm -rf "$copy_dir"
)
if [[ "$out" != *FAILED* ]] &&
    grep -qF 'PASS: bounded copy stack' <<<"$out"; then
  echo "runs     copy_deep (100000 levels, 1 MiB native stack)"
else
  echo "FAILED   copy_deep: $out"
  status=1
fi
out=$("$RIS" run test/ris/copy_rollback.ri 2>/dev/null)
if [ "$?" -eq 0 ] &&
    [ "$out" = 'PASS: failed copy restores owner usage' ]; then
  echo "runs     copy_rollback (owner and scratch growth)"
else
  echo "FAILED   copy_rollback: $out"
  status=1
fi
for name in copy_class_cycle copy_collection_cycle copy_subclass_cycle \
            copy_named_cycle; do
  expect "$name" 'copy_to refuses self-reaching class types'
done
expect copy_class_override 'remove this override'
expect copy_pointer 'build on the destination with Array nodes and indices'
expect copy_link 'copy_to refuses pointers and self-relative links'

heap_trap string_parameters

expect text_capture 'pass what the block needs as owned data (copy_to(owner))'
# These old heap-boundary refusals are safe on the object's tape now.
# Keep the original fixtures and check their text after scratch resets.
for name in text_local_field text_literal_field text_interpolation_field; do
  result=$("$RIS" run "test/ris/${name}_survives.ri" 2>&1)
  if [ "$?" -eq 0 ] && [ "$result" = "PASS: $name survives" ]; then
    echo "runs     $name (text survives)"
  else
    echo "FAILED   $name: $result"
    status=1
  fi
done
out=$("$RIS" run test/ris/text_default.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qF 'String' <<<"$out" &&
    grep -qF 'PASS: default text' <<<"$out"; then
  echo "runs     text_default"
else
  echo "FAILED   text_default: $out"
  status=1
fi

heap_trap text_literal_heap

heap_trap borrowed_text

expect class_field   "cannot use outer tape value"
expect class_task "this block becomes a proc"
expect class_share "pass Share scalar data"
expect class_finalize "tape class instances cannot finalize"
expect class_inherited_finalize "tape class instances cannot finalize"
expect class_escape "is a variable of the code around this tape block"
expect struct_field  'Use an @[OnTape] struct for request data'
expect class_var     "copy it with .copy_to(Program.tape)"
expect proc_capture  "this block becomes a proc"
expect integer_text  "integer / in text gives a Float"
expect outer_var     "is a variable of the code around this tape block"
expect scope_value   "undefined method 'id' for Nil"
expect yield_escape "is a variable of the code around this tape block"
expect yield_scope_escape "is a variable of the code around this tape block"
expect return_escape "cannot return a tape value out of its tape block"
expect break_escape "cannot break a tape value out of its tape block"
expect yield_break_escape "cannot break a tape value out of its tape block"

expect return_escape 'Copy the text with `.copy_to(owner)`'
expect outer_var '`copy_to(owner)` copies a String, Array'
# The cache copies bytes into its owner's pool before request exit.
result=$("$RIS" run samples/ris/owned_cache.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$result" = $'FIRST REQUEST\nNEXT' ]; then
  echo "runs     owned_cache (text survives request tapes)"
else
  echo "FAILED   owned_cache: $result"
  status=1
fi

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
expect raw_pointer      "to_unsafe\` of a String outside a @[TapeUnsafe] def"
expect raw_view         "String.new(pointer, size)\` outside a @[TapeUnsafe] def"
expect std/tape_unsafe_codec "reaches no \`lib\` fun or system call"
expect std/tape_unsafe_no_pointer "hands no tape pointer to the OS"
expect tape_pointer "\`unsafe_append\` outside a @[TapeUnsafe] def"
expect std/tape_pointer_codec "the pointer \`unsafe_append\` yields reaches no"
expect writer_grow      "private method 'grow' called for String::Builder"
expect tree_entry       "private constant RisTree::Entry(T) referenced"
expect array_grow       "private method 'grow' called for Array(T)"
expect array_append     "append requires Array(UInt8)"
expect refill           "\`@items\` is given a new Array in \`take\`"
expect not_flat "Holder is not flat"
expect check_free "\`first\` is @[CheckFree], and this \`[]\` checks"


# Main scratch, program values and scheduler program storage each own a tape.
# The third scope is scheduler storage, not one scope per temporary call.
for name in implicit fibers/implicit implicit_loop; do
  out=$(RIS_TAPE_STATS=1 "$RIS" run "test/ris/$name.ri" 2>&1)
  code=$?
  if [ "$code" -eq 0 ] && grep -qF 'PASS:' <<<"$out" &&
      { [ "$name" != implicit_loop ] ||
        grep -qF '3 scopes, 5 mappings made, 0 unmapped' <<<"$out"; }; then
    echo "runs     $name"
  else
    echo "FAILED   $name: $out"
    status=1
  fi
done

heap_trap escape

# Cleanup keeps LIFO order on early exits, panic and explicit exit.
out=$("$RIS" run test/ris/local.ri 2>&1)
if [ "$out" = 'PASS: local isolation, reuse, nested scopes, borrowed text, retained copy and early exits' ]; then echo "runs     local"; else echo "FAILED   local: $out"; status=1; fi
out=$("$RIS" run test/ris/local_cleanup.ri 2>/dev/null)
if [ "$out" = 'PASS: local panic cleanup and fiber switching' ]; then echo "runs     local_cleanup"; else echo "FAILED   local_cleanup: $out"; status=1; fi
out=$("$RIS" run test/ris/cleanup_order.ri 2>&1)
if [ "$out" = $'inner return\nouter return\n7\nnested\ninner break\nouter break\ninner return\nouter return\n7\ntrue\ntrue' ]; then echo "runs     cleanup_order"; else echo "FAILED   cleanup_order: $out"; status=1; fi
# Captured defer locals stay off the heap on return and panic exits.
out=$(
  exec 2>&1
  exe=$(mktemp)
  if "$RIS" build test/ris/defer_no_gc.ri -o "$exe"; then
    "$exe" AGENTS.md 2>"$exe.err"
    code=$?
    if ! grep -qF 'iyi: panic: expected defer panic' "$exe.err" ||
        ! grep -qE 'defer_no_gc.ri:[0-9]+$' "$exe.err" ||
        grep -qF 'heap allocation' "$exe.err"; then
      cat "$exe.err"
      code=1
    fi
  else
    code=1
  fi
  rm -f "$exe" "$exe.err"
  exit "$code"
)
if [ "$?" -eq 0 ] &&
    [ "$out" = $'1\nclosed\n2\nclosed\n3\nclosed\npanicked\nPASS: defer without GC' ]; then
  echo "runs     defer_no_gc"
else
  echo "FAILED   defer_no_gc: $out"; status=1
fi

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
if grep -qF '7 1,2,5,6 3,4 0 7' <<<"$out" && grep -qF "RisTree#close: 2 is not open" <<<"$out"; then echo "runs     stream"; else echo "FAILED   stream: $out"; status=1; fi

heap_trap owned

out=$("$RIS" run test/ris/writer.ri 2>&1)
if [ "$out" = '0 -42 9223372036854775807 -9223372036854775808 a&amp;b&lt;c&gt;&quot;d&#39;e <b>' ]; then echo "runs     writer"; else echo "FAILED   writer: $out"; status=1; fi

# Two pieces, String or on the tape, go out in one socket write.
out=$("$RIS" run test/ris/tape_primitives.ri 2>&1)
if [ "$out" = 'PASS: write_bytes, shift and String::Scanner' ]; then echo "runs     tape_primitives"; else echo "FAILED   tape_primitives: $out"; status=1; fi
out=$("$RIS" run test/ris/socket_pair.ri 2>&1)
if [ "$out" = 'PASS: two pieces in one write, String and on the tape, 1 MiB' ]; then echo "runs     socket_pair"; else echo "FAILED   socket_pair: $out"; status=1; fi
out=$("$RIS" run test/ris/socket_pieces.ri 2>&1)
if [ "$out" = 'PASS: 203 pieces in order, empty ones and 1 MiB among them' ]; then echo "runs     socket_pieces"; else echo "FAILED   socket_pieces: $out"; status=1; fi
out=$(RIS="$RIS" bash test/ris/http_continue.sh 2>&1)
if [ "$?" -eq 0 ] &&
    [ "$out" = 'PASS: pending continue, buffering, framing, failure and cancellation' ]; then
  echo "runs     http_continue"
else
  echo "FAILED   http_continue: $out"; status=1
fi
expect http_server_listener 'Server.serve(host, port, config, Handler)'
expect http_server_resource_config 'open and use resources'
out=$(RIS="$RIS" python3 test/ris/http_prefork.py 2>&1)
if [ "$?" -eq 0 ]; then
  printf '%s\n' "$out"
else
  echo "FAILED   http_prefork: $out"; status=1
fi
out=$("$RIS" run test/ris/answer.ri 2>&1)
if [ "$out" = 'PASS: read and answered on the tape, fast path and not' ]; then echo "runs     answer"; else echo "FAILED   answer: $out"; status=1; fi
out=$("$RIS" run test/ris/query.ri 2>&1)
if [ "$out" = 'PASS: read as Params reads, nothing on the heap' ]; then echo "runs     query"; else echo "FAILED   query: $out"; status=1; fi
out=$("$RIS" run test/ris/truncate.ri 2>&1)
if grep -qF "PASS: cut back and written over" <<<"$out" && grep -qF "truncate to 1 of 0 bytes" <<<"$out"; then echo "runs     truncate"; else echo "FAILED   truncate: $out"; status=1; fi

heap_trap json

heap_trap json_buffer
expect json_builder_escape 'is a variable of the code around this tape block'

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
out=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 "$RIS" run \
  test/ris/side_warm.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qF '10002 scopes, 5 mappings made, 0 unmapped' <<<"$out" &&
    grep -qF '0 growth moves' <<<"$out" &&
    grep -qF '0 side regions (0 transfer bytes copied)' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     side_warm (10,000 scopes, no copies or fresh mappings)"
else
  echo "FAILED   side_warm: $out"; status=1
fi
out=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 "$RIS" run \
  test/ris/side_spares.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qF 'PASS: mixed side spares reused' <<<"$out" &&
    grep -qF '4 mappings made, 0 unmapped' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     side_spares (mixed reservations reused 10,000 times)"
else
  echo "FAILED   side_spares: $out"; status=1
fi
out=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 "$RIS" run \
  test/ris/query_scope.ri 2>&1)
code=$?
mappings=$(sed -n \
  's/^ris tape:.*scopes, \([0-9]*\) mappings made.*/\1/p' <<<"$out")
if [ "$code" -eq 0 ] &&
    grep -qF 'PASS: query scopes reuse reservations' <<<"$out" &&
    [ -n "$mappings" ] && [ "$mappings" -le 8 ] &&
    grep -qF '0 side regions (0 transfer bytes copied)' <<<"$out" &&
    grep -qF '0 growth moves' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     query_scope (10,000 rounds, bounded reservations)"
else
  echo "FAILED   query_scope: $out"; status=1
fi
out=$("$RIS" run test/ris/side.ri 2>&1)
if [ "$out" = $'round 0: intact\nround 1: intact\nround 2: intact' ]; then echo "runs     side"; else echo "FAILED   side: $out"; status=1; fi
out=$("$RIS" run test/ris/scope_free.ri 2>&1)
if [ "$out" = $'round 99999\nwhile frees: true\nblock wrote 200000\nblock frees: true\nkept stays: true true\n123\ndef frees: true 5\nresult stays: true 42' ]; then echo "runs     scope_free"; else echo "FAILED   scope_free: $out"; status=1; fi
out=$("$RIS" run test/ris/scope_keep.ri 2>&1)
if [ "$out" = "50000 50000 9" ]; then echo "runs     scope_keep"; else echo "FAILED   scope_keep: $out"; status=1; fi

# Retain 10,000 small results without retaining 64 KiB per-call scratch.
out=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 "$RIS" run \
  test/ris/pending_result.ri 2>&1)
if [ "$?" = 0 ] &&
   grep -qF 'PASS: pending results and borrowed views' <<<"$out" &&
   grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out" &&
   grep -qF '2 scopes, 6 mappings made, 0 unmapped, 0 tapes grown' <<<"$out"; then
  echo "runs     pending_result (bounded scratch, borrowed input stays a view)"
else
  echo "FAILED   pending_result: $out"; status=1
fi
out=$("$RIS" run test/ris/pending_shapes.ri 2>&1)
if [ "$?" = 0 ] &&
   [ "$out" = 'PASS: pending structs, arrays, trees and early returns' ]; then
  echo "runs     pending_shapes"
else
  echo "FAILED   pending_shapes: $out"; status=1
fi

out=$("$RIS" run test/ris/pending_regions.ri 2>&1)
if [ "$?" = 0 ] &&
   [ "$out" = 'PASS: pending results survive grown and side scratch rollback' ]; then
  echo "runs     pending_regions"
else
  echo "FAILED   pending_regions: $out"; status=1
fi
out=$("$RIS" run test/ris/pending_cleanup.ri 2>/dev/null)
if [ "$?" = 0 ] &&
   [ "$out" = 'PASS: pending panic restores caller and releases staging' ]; then
  echo "runs     pending_cleanup"
else
  echo "FAILED   pending_cleanup: $out"; status=1
fi

out=$("$RIS" run test/ris/in_place.ri 2>&1)
if [ "$out" = $'<li>item n0</li><li>item n1</li><li>item n2</li>\n<li>item n9</li>\nin place: true 1' ]; then echo "runs     in_place"; else echo "FAILED   in_place: $out"; status=1; fi
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
heap_trap to_heap
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

heap_trap string_arguments

# Generic std classes and crypto inputs use checked tape storage.
for name in std_generic_tape std_small_tape curve_views mlkem_views shlex base32 \
            semantic_version uuid; do
  out=$(RIS_HEAP_STATS=1 "$RIS" run "test/ris/$name.ri" 2>&1)
  if [ "$?" -eq 0 ] &&
      grep -qE 'PASS:|ALL CHECKS PASSED' <<<"$out" &&
      grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
    echo "runs     $name (no GC)"
  else
    echo "FAILED   $name: $out"; status=1
  fi
done

# HPACK's tape overload agrees with the retained API across tape scopes.
out=$("$RIS" run --release test/ris/hpack.ri 2>&1)
if [ "$out" = \
  'PASS: tape HPACK fields, retained tables and malformed input' ]; then
  echo "runs     hpack"
else
  echo "FAILED   hpack: $out"
  status=1
fi


# HTTP diagnostics, query serialization and URI use the caller's tape.
for name in http_head_tape params_write_tape uri_tape idna_tape; do
  out=$(RIS_HEAP_STATS=1 "$RIS" run "test/ris/$name.ri" 2>&1)
  if [ "$?" -eq 0 ] &&
      grep -qF 'zero heap' <<<"$out" &&
      grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
    echo "runs     $name (no GC)"
  else
    echo "FAILED   $name: $out"; status=1
  fi
done

# uri_legacy: the String URI.parse path loses normalize fields (TODO.md).

heap_trap http_head_legacy

# Log text, numeric formatting and quoting use the caller's tape.
out=$(RIS_HEAP_STATS=1 "$RIS" run \
  test/ris/text_format_tape.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qF 'text formatting: zero heap' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     text_format_tape (no GC)"
else
  echo "FAILED   text_format_tape: $out"; status=1
fi
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/log_metadata.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qF 'PASS: metadata, binding and nested contexts on tape' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     log_metadata (no GC)"
else
  echo "FAILED   log_metadata: $out"; status=1
fi
expect log_metadata_escape 'is a variable of the code around this tape block'
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/log_metadata.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qF 'PASS: metadata, binding and nested contexts on tape' <<<"$out"; then
  echo "runs     log_metadata (parallel inherited context)"
else
  echo "FAILED   log_metadata parallel: $out"; status=1
fi
out=$("$RIS" run test/ris/log_tape.ri 2>&1)
if [ "$?" -eq 0 ] &&
    [ "$out" = 'logging: tape IO and retaining backend' ]; then
  echo "runs     log_tape (metadata and retaining backend)"
else
  echo "FAILED   log_tape: $out"; status=1
fi
out=$(
  for name in number_format_error number_format_signed_error; do
    result=$(RIS_HEAP_STATS=1 "$RIS" run \
      "test/ris/$name.ri" 2>&1)
    if [ "$?" -ne 0 ] &&
        grep -qF 'iyi: panic: base out of range' <<<"$result" &&
        grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$result"; then
      echo "runs     $name (no GC error)"
    else
      echo "FAILED   $name: $result"
      exit 1
    fi
  done
)
if [ "$?" -eq 0 ]; then
  echo "$out"
else
  echo "$out"; status=1
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
# refused; the same lexer on String::Scanner is not.
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
out=$("$RIS" run test/ris/fault_no_heap.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'fault path: zero heap' ]; then
  echo "runs     fault_no_heap (no GC)"
else
  echo "FAILED   fault_no_heap: $out"; status=1
fi
out=$("$RIS" run test/ris/cleanup_current.ri 2>/dev/null)
if [ "$?" -eq 0 ] && [ "$out" = $'2\n4\n5\n7\nalive' ]; then
  echo "runs     cleanup_current"
else
  echo "FAILED   cleanup_current: $out"; status=1
fi
out=$("$RIS" run test/ris/task_limit.ri 2>&1)
if [ "$?" -eq 1 ] &&
    [ "$out" = 'ris: fatal: group task limit 2147483647 reached' ]; then
  echo "fatal    task_limit (no GC)"
else
  echo "FAILED   task_limit: $out"; status=1
fi
out=$("$RIS" run test/ris/unwind_no_heap.ri 2>&1)
if [ "$?" -eq 1 ] &&
    [ "$out" = 'ris: fatal: raise during cleanup unwinding' ]; then
  echo "fatal    unwind_no_heap (no GC)"
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

# A reset must prove that every old view is finished or copied out.
for kind in array hash field returned block def task union start_view \
            conditional_field; do
  expect "text_reset_$kind" 'copy_to(owner)'
done

# Text bindings reserve lazily and copy only their initial bytes.
expect text_grow_owner 'declare the append method in the owning class'
expect text_param_append 'Take `io : String::Builder`'
expect text_io_parameter 'io : String::Builder'
for kind in field parameter literal; do
  expect "text_lend_$kind" 'Pass a local String variable started from text'
done
expect text_plain_builder 'only appends and is read back: write `text = ""`'
expect text_plain_build 'this String.build only appends: write `io = ""`'
# ris fix applies the compiler's own edits: Crystal-style text becomes ris.
out=$(f="${TMPDIR:-/tmp}/plain_builder.ri"; cp test/ris/fix/plain_builder.ri "$f" && "$RIS" fix "$f" >/dev/null 2>&1 && diff test/ris/fix/plain_builder.expected "$f" && "$RIS" run "$f" 2>&1)
if [ "$out" = "hello, ris" ]; then echo "runs     fix plain_builder"; else echo "FAILED   fix plain_builder: $out"; status=1; fi
for rule in plain_build plain_build_inline io_parameter; do
  result=$(f="${TMPDIR:-/tmp}/fix_$rule.ri";
    cp "test/ris/fix/$rule.ri" "$f" &&
    "$RIS" fix "$f" >/dev/null 2>&1 &&
    diff "test/ris/fix/$rule.expected" "$f" &&
    "$RIS" fix "$f" >/dev/null 2>&1 &&
    diff "test/ris/fix/$rule.expected" "$f" &&
    "$RIS" run "$f" 2>&1)
  if [ "$result" = "hello, ris" ]; then
    echo "runs     fix $rule"
  else
    echo "FAILED   fix $rule: $result"; status=1
  fi
done
out=$("$RIS" run test/ris/text_field_kinds.ri 2>&1)
if grep -qF 'PASS: text companions only for text fields' <<<"$out"; then echo "runs     text_field_kinds"; else echo "FAILED   text_field_kinds: $out"; status=1; fi
out=$("$RIS" run test/ris/text_builder_kept.ri 2>&1)
if grep -qF 'PASS: builders that do more than append' <<<"$out"; then echo "runs     text_builder_kept"; else echo "FAILED   text_builder_kept: $out"; status=1; fi
out=$("$RIS" run test/ris/text_param.ri 2>&1)
if grep -qF 'PASS: appends through parameters' <<<"$out"; then echo "runs     text_param"; else echo "FAILED   text_param: $out"; status=1; fi
out=$(RIS_TAPE_STATS=1 "$RIS" run test/ris/text_grow.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qxF 'PASS: text grows in locals and fields' <<<"$out" &&
    grep -qF "0 growth moves off the tape's end (0 bytes copied)" <<<"$out" &&
    grep -qF '0 side regions (0 transfer bytes copied)' <<<"$out"; then
  echo "runs     text_grow (locals, fields, reset reuse, zero moves)"
else
  echo "FAILED   text_grow: $out"; status=1
fi

# Reserved side growth keeps addresses and uses bounded mappings.
# Counts include the program storage mapping for standard streams.
out=$(RIS_TAPE_STATS=1 "$RIS" run test/ris/stable_growth.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qF 'PASS: stable interleaved growth' <<<"$out" &&
    grep -qF '0 growth moves' <<<"$out" &&
    grep -qF '5 mappings made' <<<"$out" &&
    grep -qF '0 side regions (0 transfer bytes copied)' <<<"$out"; then
  echo "runs     stable_growth (no GC, bounded mappings)"
else
  echo "FAILED   stable_growth: $out"; status=1
fi
out=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 "$RIS" run \
  test/ris/stable_components.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qF 'PASS: builder and tree stable before first growth' <<<"$out" &&
    grep -qF '6 mappings made, 0 unmapped' <<<"$out" &&
    grep -qF '0 growth moves' <<<"$out" &&
    grep -qF '0 side regions (0 transfer bytes copied)' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     stable_components (no GC, views before first growth)"
else
  echo "FAILED   stable_components: $out"; status=1
fi
out=$("$RIS" run test/ris/side_overflow.ri 2>&1)
if [ "$?" -eq 1 ] &&
    [ "$out" = 'iyi: tape side reservation exhausted: 134217729' ]; then
  echo "fatal    side_overflow (no GC)"
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
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/heap_zero.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qF 'zero42' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     heap_zero (no GC)"
else
  echo "FAILED   heap_zero: $out"
  status=1
fi
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/heap_class.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qF '42' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     heap_class (no GC)"
else
  echo "FAILED   heap_class: $out"
  status=1
fi
# heap_allocator traps again when the bump allocator goes (TODO.md).
# Exercise read boundaries over the full keep-alive workload.
out=$(RIS_HEAP_STATS=1 "$RIS" run --release \
  samples/ris/serve.ri -- answer 2>&1)
if [ "$?" -eq 0 ] &&
    [ "$(grep -v '^ris heap:' <<<"$out")" = '200000 requests' ] &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     serve (200000 requests)"
else
  echo "FAILED   serve full loop: $out"
  status=1
fi
out=$("$RIS" run test/ris/server_owners.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qF 'task-local shutdown' <<<"$out"; then
  echo "runs     server_owners (no GC, cancellation cleanup)"
else
  echo "FAILED   server_owners: $out"; status=1
fi
# Repeated joined groups must reuse task and request tape storage.
out=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 "$RIS" run --release \
  test/ris/server_groups.ri 2>&1)
code=$?
mappings=$(sed -n \
  's/^ris tape:.*scopes, \([0-9]*\) mappings made.*/\1/p' <<<"$out")
if [ "$code" -eq 0 ] &&
    grep -qxF 'PASS: server groups' <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out" &&
    [ -n "$mappings" ] && [ "$mappings" -le 29 ] &&
    grep -qF '0 growth moves' <<<"$out" &&
    grep -qF '0 side regions (0 transfer bytes copied)' <<<"$out"; then
  echo "runs     server_groups (20 groups, 20000 requests, bounded tape)"
else
  echo "FAILED   server_groups: $out"
  status=1
fi
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/heap_fibers.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qF 'fiber42' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     heap_fibers (no GC runtime bookkeeping)"
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
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/heap_fiber_capture.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qxF '42' <<<"$out" &&
    grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     heap_fiber_capture (no GC owned capture)"
else
  echo "FAILED   heap_fiber_capture zero heap: $out"
  status=1
fi
# heap_handles and heap_io trap again when the bump allocator goes
# (TODO.md, Goose-style std).
out=$("$RIS" heap --user test/ris/heap_fields.ri 2>&1)
if [ "$?" -eq 0 ] && ! grep -qE '^class: [1-9]' <<<"$out" &&
    grep -qF 'array: 1' <<<"$out"; then
  echo "census   heap_fields (instance initializer reached)"
else
  echo "FAILED   heap_fields: $out"
  status=1
fi
out=$("$RIS" heap --user test/ris/heap_kinds.ri 2>&1)
if [ "$?" -eq 0 ] && ! grep -qE '^class: [1-9]' <<<"$out" &&
    grep -qF 'string: 1' <<<"$out" && grep -qF 'array: 1' <<<"$out" &&
    grep -qF 'hash: 2' <<<"$out" && grep -qF 'closure: 1' <<<"$out"; then
  echo "census   heap_kinds (unused def omitted)"
else
  echo "FAILED   heap_kinds: $out"
  status=1
fi

for name in program_alias program_helper program_nested_alias \
    program_loop_alias; do
  out=$(RIS_HEAP_STATS=1 "$RIS" run "test/ris/$name.ri" 2>&1)
  if [ "$?" -eq 0 ] &&
      grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
    echo "runs     $name (owned container store)"
  else
    echo "FAILED   $name: $out"; status=1
  fi
done
expect program_local_init 'copy it with .copy_to(Program.tape)'
expect program_copy_forged 'program initializer is private'
# Without a collector there is no IyiThread yet (thread.iyi is gated on
# the collector); these return when kernel threads do (TODO.md).
expect program_threads 'undefined constant IyiThread'
expect program_field_thread 'undefined constant IyiThread'
for name in program_tape program_growth; do
  out=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 \
    "$RIS" run "test/ris/$name.ri" 2>&1)
  if [ "$?" -eq 0 ] && grep -qF 'PASS: program' <<<"$out" &&
      grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
    echo "runs     $name (no GC)"
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
# program_readers needs kernel threads; it returns with IyiThread.
out=$("$RIS" run test/ris/program_text.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'value 42' ]; then
  echo "runs     program text constant"
else
  echo "FAILED   program text constant: $out"
  status=1
fi

# Run heap workloads after the other gates to avoid compiler contention.
# Keep their fixed timeouts: a hung census must still fail.
python3 test/ris/heap_check.py || status=1

if [ "$status" -eq 0 ]; then
  echo "PASS: all ris checks"
else
  echo "FAIL: ris checks"
fi
bash scripts/kill-tests.sh
exit $status
