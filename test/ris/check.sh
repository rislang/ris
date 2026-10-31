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

# The first parallel spawn, made in a block iteration's tape scope, lists
# the workers in program storage, not in that scope.
out=$("$RIS" run test/ris/parallel_first_spawn_scope.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = '63' ]; then
  echo 'runs     parallel_first_spawn_scope'
else
  echo "FAILED   parallel_first_spawn_scope: $out"; status=1
fi

# Two types' fields of one name stay two fields in the shrink checker.
out=$("$RIS" run test/ris/field_fold_owner.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = 'kept' ]; then
  echo 'runs     field_fold_owner'
else
  echo "FAILED   field_fold_owner: $out"; status=1
fi

# A String's `+` stored back in the Hash it read leaves no view live.
out=$("$RIS" run test/ris/hash_join_copy.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = '2' ]; then
  echo 'runs     hash_join_copy'
else
  echo "FAILED   hash_join_copy: $out"; status=1
fi

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

# An Array(T)? beside a borrowed Array::View argument takes the whole
# union; a view never reaches an Array parameter (it crashed codegen).
out=$("$RIS" run test/ris/borrowed_nilable_array.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = $'2\n3\n2' ]; then
  echo 'runs     borrowed_nilable_array'
else
  echo "FAILED   borrowed_nilable_array: $out"; status=1
fi
expect view_into_array 'An Array::View(T) is not an Array(T)'

# Array::View#index answers the place in the view, not in the Array.
out=$("$RIS" run test/ris/view_index.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = $'1\ntrue\ntrue\n1\ntrue\n2' ]; then
  echo 'runs     view_index'
else
  echo "FAILED   view_index: $out"; status=1
fi

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

# Tasks capture Share values, or take a value handed off (SPEC 5.1).
expect task_capture_mutable 'build tape values inside the spawn'
expect task_capture_assigned 'a mutable borrow across tasks'
expect task_tape_block_capture 'this task captures `word`, set inside a `tape` block'
out=$("$RIS" run test/ris/task_tape_block.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = $'j2\nb1\nw3' ]; then
  echo "runs     task_tape_block (group inside, capture set before)"
else
  echo "FAILED   task_tape_block: $out"; status=1
fi
expect task_handoff_alias '`other = server` keeps a second name for the value handed to the task'
expect task_reached_class_var 'changes `@@total` through `add`, which the task calls'
expect task_reached_constant 'changes `TOTAL` through `add`, which the task calls'
out=$("$RIS" run test/ris/task_reached_state.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = '16' ]; then
  echo "runs     task_reached_state (reads and own data through calls)"
else
  echo "FAILED   task_reached_state: $out"; status=1
fi
# std's text, too, is `s = ""` and `<<`: every std module compiles under
# the plain-builder refusal.
if out=$("$RIS" build --no-codegen test/ris/std_text_plain.ri 2>&1); then
  echo "runs     std_text_plain (no plain builder in std)"
else
  echo "FAILED   std_text_plain: $out"; status=1
fi
expect task_handoff_reused 'the task owns it now'
expect task_handoff_kept '`Holder.new(server)` may keep `server` (through `initialize`)'
expect task_reached_proc 'changes `@@total` in a proc the task calls (made at line 7)'
expect task_reached_proc_kept 'changes `@@seen` through `fire`, which the task calls'
out=$("$RIS" run test/ris/task_reached_proc.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = $'15\n2\ntrue' ]; then
  echo "runs     task_reached_proc (procs read state, change own data; read-only call before a hand-off)"
else
  echo "FAILED   task_reached_proc: $out"; status=1
fi
expect select_gone 'ris has no select'
expect channel_gone 'undefined constant Channel'
expect mutex_gone 'ris has no std/mutex'
expect http_tls_config_gone 'HTTPClient.new(tls: config)'
expect http_upgrade_block 'take_over(socket, leftover, response)'
expect http_parse_head_text 'Server.parse_head(bytes, 0, true)'

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

# Pipe ends are pooled: 5,000 pipes in rounds take program storage in
# the first round only; a handle kept past its close is refused.
out=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 "$RIS" run test/ris/pipe_reuse.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qxF 'PASS: pipe reuse' <<<"$out" &&
    grep -qxF 'program storage after the first round: steady' <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     pipe_reuse (5,000 pipes, steady program storage)"
else
  echo "FAILED   pipe_reuse: $(grep -v '^ris tape\|  at ' <<<"$out")"
  status=1
fi

# Interpolated output and panic text from iyi library code stay on tape.
# A library def's interpolated String lands on the caller's tape.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/interpolation_retained.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qE '^PASS: interpolation retained [0-9]+$' <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo 'runs     interpolation_retained (on the caller tape, no heap)'
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
    grep -qF 'PASS: autocert cancellation' <<<"$out" &&
    grep -qF 'PASS: autocert reuse' <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
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

out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/task_value_nested.ri 2>&1)
if [ "$?" -eq 0 ] && [ "$out" = $'i1\na2\n2\nx3\nv5\nt6\n7\nris heap: 0 allocations, 0 bytes' ]; then
  echo "runs     task_value_nested (struct in struct, Array/Hash/Tuple of structs)"
else
  echo "FAILED   task_value_nested: $out"; status=1
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
expect nested_links 'a nested Array cannot hold self-relative links'
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

# Growing text survives module artifacts without a second lowering.
result=$(python3 test/ris/iyimod_text_growth.py 2>&1)
if [ "$?" -eq 0 ]; then
  printf '%s\n' "$result"
else
  echo "FAILED   iyimod_text_growth: $result"
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

# std/yaml on the caller tape: TapeValue read, dumped, read back; no heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/yaml.ri 2>&1)
want='name: café
list:
  - 1
  - true
  - null
  - 0.125
quoted: "a\nb"
- - 1
  - - 2
  - 3
- - 4
  - - 5
    - 6
[[1, [2], 3], [4, [5, 6]]]
{"name" => "café", "list" => [1, true, nil, 0.125], "quoted" => "a\nb"}
2
a: 1
- x
- k: v
p 3 a,b true
name: p
x: 3
tags:
  - a
  - b
scale: null
PASS: yaml tape
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     yaml (read, dump and derive on the tape, no heap)'
else
  echo "FAILED   yaml: $out"; status=1
fi

# std/toml on the caller tape: TapeAny read, dumped, read back; no heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/toml.ri 2>&1)
want='"title = \"café\"\n\n[db]\nports = [80, 443]\n"
296638320
the key x is defined twice at line 2, column 1
"x = \"line\\nquote\\\"\"\n"
"x = \"multiline\\ntext\"\n"
"[x]\na = 1\nb = [\"a\", true]\n\n[y]\nz = 2\n"
"[[a]]\nx = 1\n\n[[a]]\nx = 2\n\n[a.b]\ny = 3\n"
"x = -9223372036854775808\ny = 9223372036854775807\n"
"a = nan\nb = -inf\nc = inf\nd = -0.0\n"
"a = 1979-05-27\nb = 07:32:00.123\nc = 1979-05-27T07:32:00\n"
"x = 0.1\n"
"[root]\ntail = 5\n\n[root.a]\nafter = 4\n\n[root.a.nested]\nb = [1, [2], 3]\n"
{ ports = [80, 443] }
h 8080 a,b true
host = "h"
port = 8080
tags = ["a", "b"]
PASS: toml tape
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     toml (read, dump and derive on the tape, no heap)'
else
  echo "FAILED   toml: $out"; status=1
fi

# std/xml on the caller tape: XmlTree node array read, built, copied; no heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/xml.ri 2>&1)
want='<?xml version="1.0" encoding="UTF-8"?>
<root xmlns:p="urn:x" a="&amp;"><p:child>café &lt;<![CDATA[raw]]></p:child><!--ok--><item n="1"/><item n="2"><item n="3"/></item></root>
p:child child urn:x
1,2,3
root
4
true
<?xml version="1.0" encoding="UTF-8"?>
<list kind="c&quot;d" size="1"><entry id="e1">x &amp; y</entry><!--end--></list>
a < A
true
PASS: xml tape
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     xml (node array read, built, written, copied; no heap)'
else
  echo "FAILED   xml: $out"; status=1
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
    # Per task: its tape, local_tape, and the result region that keeps
    # the panic text until the group ends (one mapping, reused).
    grep -qF '302 scopes, 7 mappings made, 0 unmapped' <<<"$out"; then
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
expect class_share 'ClassShareValue is a tape type'
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

expect ffi_pointerof    "\`pointerof\` outside an @[Ffi] module"
expect ffi_pointer      "\`Pointer\` outside an @[Ffi] module"
expect ffi_to_unsafe    "Read a byte with \`s.byte_at(i)\`"
expect ffi_lib          "a \`lib\` block outside an @[Ffi] module"
expect ffi_string_new   "Build it with \`String.build(capacity)"
expect pointer_unsafe_reason "takes the reason the def needs a pointer"
expect pointer_unsafe_stray  "@[PointerUnsafe] marks a def"
expect pointer_unsafe_lib    "a \`lib\` block outside an @[Ffi] module"
expect pointer_unsafe_to_unsafe "pass \`text.to_unsafe\` straight to the \`lib\` fun"
expect ffi_to_unsafe_stored "pass \`text.to_unsafe\` straight to the \`lib\` fun"
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
        grep -qF '2 scopes, 4 mappings made, 0 unmapped' <<<"$out"; }; then
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


out=$("$RIS" run test/ris/fibers/task_stop.ri 2>&1)
if [ "$out" = "stopped 1, others 2 7" ]; then echo "runs     fibers/task_stop"; else echo "FAILED   fibers/task_stop: $out"; status=1; fi
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
# std/websocket's frames on the caller tape, and its reader over a socket:
# masked, fragmented, ping, a message past the read buffer, close; no heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/websocket.ri 2>&1)
if [ "$?" -eq 0 ] &&
    grep -qxF 'PASS: websocket caller tape and explicit retained copy' \
      <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo 'runs     websocket (frames on the caller tape, no heap)'
else
  echo "FAILED   websocket: $out"; status=1
fi
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/websocket_reader.ri 2>&1)
want='text hello
binary 3 bytes, last 255
text fragmented
text 50000 abc..zab
binary 50000 abc..zab
closed
closed
code 1000 bye
answer 11 138 5
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     websocket_reader (frames read on the tape, no heap)'
else
  echo "FAILED   websocket_reader: $out"; status=1
fi
# A real loopback handshake: connect offers permessage-deflate, upgrade
# parses the offer; then raw offers with a quoted parameter.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/websocket_handshake.ri 2>&1)
want='protocol chat
deflate false false
305
echo hello hello
HTTP/1.1 101 Switching Protocols
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
Sec-WebSocket-Extensions: permessage-deflate; server_no_context_takeover
HTTP/1.1 400 Bad Request
Sec-WebSocket-Extensions is not a list of extensions: the value of a, "b\"c", is not a token
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     websocket_handshake (connect and upgrade, no heap)'
else
  echo "FAILED   websocket_handshake: $out"; status=1
fi
# std/http client: coded answers decoded through BodyFeed, an io Reader.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/http_coding.ri 2>&1)
want='/gzip 200 87000 coded body, line after line.  true
/zlib 200 87000 coded body, line after line.  true
/bare 200 87000 coded body, line after line.  true
/zstd 200 87000 coded body, line after line.  true
/bad true
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     http_coding (gzip, deflate and zstd answers decoded through an io Reader)'
else
  echo "FAILED   http_coding: $out"; status=1
fi
# A task-owned Conn's buffer grows in its own reservation of the
# connection's tape, in place: heads up to 900 KB and 1 MB bodies on one
# keep-alive connection take no program storage per growth (2 MB before).
out=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 timeout 120 "$RIS" run \
  test/ris/http_conn_growth.ri 2>&1)
taken=$(printf '%s\n' "$out" | sed -n 's/^ris program storage: \([0-9]*\) .*/\1/p')
lines=$(printf '%s\n' "$out" | grep -v '^ris ')
want='100000 true
900000 true
300000 true
1000 true
600000 true'
if [ "$lines" = "$want" ] && [ -n "$taken" ] && [ "$taken" -lt 65536 ] &&
   printf '%s\n' "$out" | grep -qx 'ris heap: 0 allocations, 0 bytes'; then
  echo "runs     http_conn_growth (keep-alive growth in place, $taken B program)"
else
  echo "FAILED   http_conn_growth: $out"; status=1
fi
# Many requests on one keep-alive connection: each request's head, parse
# and answer are freed when it ends (serve_h1's per-request tape block),
# so the connection's mappings are the same for 200 requests as for 5000.
exe=$(mktemp)
if out=$("$RIS" build test/ris/http_keepalive_scope.ri -o "$exe" 2>&1); then
  few=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 timeout 120 "$exe" 200 2>&1)
  many=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 timeout 300 "$exe" 5000 2>&1)
  maps() { printf '%s\n' "$1" | sed -n 's/^ris tape: .* \([0-9]*\) mappings made.*/\1/p'; }
  if printf '%s\n' "$few" | grep -qx '200 true' &&
     printf '%s\n' "$many" | grep -qx '5000 true' &&
     printf '%s\n' "$many" | grep -qx 'ris heap: 0 allocations, 0 bytes' &&
     [ -n "$(maps "$few")" ] && [ "$(maps "$few")" = "$(maps "$many")" ]; then
    echo "runs     http_keepalive_scope ($(maps "$many") mappings for 200 and 5000 requests)"
  else
    echo "FAILED   http_keepalive_scope: $few / $many"; status=1
  fi
else
  echo "FAILED   http_keepalive_scope: $out"; status=1
fi
rm -f "$exe"
# The same for Server.answer's loop (tape_connection): plain requests
# answered in place and chunked ones read the slow way, alternating.
exe=$(mktemp)
if out=$("$RIS" build test/ris/http_answer_scope.ri -o "$exe" 2>&1); then
  few=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 timeout 120 "$exe" 200 2>&1)
  many=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 timeout 300 "$exe" 5000 2>&1)
  maps() { printf '%s\n' "$1" | sed -n 's/^ris tape: .* \([0-9]*\) mappings made.*/\1/p'; }
  if printf '%s\n' "$few" | grep -qx '200 true' &&
     printf '%s\n' "$many" | grep -qx '5000 true' &&
     printf '%s\n' "$many" | grep -qx 'ris heap: 0 allocations, 0 bytes' &&
     [ -n "$(maps "$few")" ] && [ "$(maps "$few")" = "$(maps "$many")" ]; then
    echo "runs     http_answer_scope ($(maps "$many") mappings for 200 and 5000 requests)"
  else
    echo "FAILED   http_answer_scope: $few / $many"; status=1
  fi
else
  echo "FAILED   http_answer_scope: $out"; status=1
fi
rm -f "$exe"
out=$(RIS="$RIS" timeout 200 bash test/ris/http2_conn_growth.sh 2>&1)
case "$out" in
  "ok "*) echo "runs     http2_conn_growth (1 MiB h2c POSTs, ${out#ok } B program)";;
  skipped) echo 'skipped  http2_conn_growth (no curl with HTTP/2)';;
  *) echo "FAILED   http2_conn_growth: $out"; status=1;;
esac
# Linux's connect race: one task, every attempt in flight on its own
# epoll; staggered starts, refusals, deadline, cancel, losers closed.
if [ "$(uname -s)" = Linux ]; then
  out=$(RIS_HEAP_STATS=1 timeout 120 "$RIS" run test/ris/socket_race.ri 2>&1)
  if grep -qxF 'PASS: socket race' <<<"$out" &&
      grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
    echo 'runs     socket_race (one task, epoll of attempts, losers closed)'
  else
    echo "FAILED   socket_race: $out"; status=1
  fi
fi
# std/udp on the caller tape: datagrams received into String room or an
# Array, connected sends, a 60000-byte datagram; no heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/udp.ri 2>&1)
want='true
ping loopback 13 127.0.0.1 true
pong 127.0.0.1
8 49 56 127.0.0.1
hi
true
60000 250 10
true
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     udp (datagrams on the tape, no heap)'
else
  echo "FAILED   udp: $out"; status=1
fi
# std/ini on the caller tape as a RisIni: BOM, CRLF, repeated section
# and key, Unicode blanks, build round-trip, a retained copy; no heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/ini.ri 2>&1)
want=',s,t
yes last v=w 3
true
"prefix:top = yes\n[s]\na = last\n\n[t]\nk = v=w\n\n"
true
café
true
true
v=w
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     ini (RisIni on the tape, no heap)'
else
  echo "FAILED   ini: $out"; status=1
fi
# std/otp on the caller tape: RFC 4226 and 6238 vectors, a key URI
# built and parsed back, a refused URI; no heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/otp.ri 2>&1)
want='755224,287082,359152,969429
94287082
07081804
true
false
otpauth://totp/Ex%20Co:ada%40example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Ex%20Co&algorithm=SHA256&digits=8&period=60
ada@example.com Ex Co 8 60 true
otpauth: no secret parameter
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     otp (HOTP, TOTP and key URIs on the tape, no heap)'
else
  echo "FAILED   otp: $out"; status=1
fi
# std/netip on the caller tape: IPv4/IPv6 text, an IPv4 tail, a zone,
# refusals, prefixes, subnets and a PrefixSet; no heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/netip.ri 2>&1)
want='192.168.1.20 -> 192.168.1.20 private=true loopback=false
::1 -> ::1 private=false loopback=true
2001:db8:0:0:0:0:2:1 -> 2001:db8::2:1 private=false loopback=false
::ffff:10.0.0.1 -> ::ffff:10.0.0.1 private=true loopback=false
fe80::1%eth0 -> fe80::1%eth0 private=false loopback=false
1.2.3 -> netip: "1.2.3" is not an IPv4 address: 3 octets, not four
01.2.3.4 -> netip: "01.2.3.4" is not an IPv4 address: the octet "01" has a leading zero, which some readers take for octal
1::2::3 -> netip: "1::2::3" is not an IPv6 address: more than one '\''::'\''
10.1.0.0/16 contains true
10.1.0.0/18 10.1.64.0/18 10.1.128.0/18 10.1.192.0/18
netip: "10.1.2.3/8" is not a prefix: host bits are set past /8; Prefix.parse(text, mask: true) clears them
2 true 2001:db8::/32
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     netip (addresses and prefixes on the tape, no heap)'
else
  echo "FAILED   netip: $out"; status=1
fi
# std/debug under ris: a panic's frames walked and named from the binary.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/debug.ri 2>&1); code=$?
if [ "$code" -ne 0 ] && grep -qxF 4 <<<"$out" &&
    grep -qF 'panic: deliberate 3' <<<"$out" &&
    grep -qE '^0 +inner_fails at .*test/ris/debug.ri:9:3$' <<<"$out" &&
    grep -qE '^1 +outer_calls at .*test/ris/debug.ri:14:3$' <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo 'runs     debug (backtrace named, no heap)'
else
  echo "FAILED   debug: $out"; status=1
fi
# std/csv on the caller tape: parse/build round-trip, readers over a
# String and a stream, a writer, an error, edge rows; no heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/csv.ri 2>&1)
want='3
id|name|says
1|Ada|hi, "there"
2|Bob|two
lines
true
52
2 Ada=11
3 Bob=9
a/b/c
x/y
csv: unterminated quoted field, opened at line 2, column 1
"name,\" pad\",\"say \"\"x\"\"\"\r\n\"\"\r\n"
2
3 1 true true
true
a
true
hi, "there"
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     csv (parse, read and write on the tape, no heap)'
else
  echo "FAILED   csv: $out"; status=1
fi
# std/smtp on the caller tape: dot-stuffing and a loopback session
# (EHLO, AUTH, DATA, a refused RCPT, QUIT); no heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/smtp.ri 2>&1)
want='"prefix:..one\r\n...two\r\nthree\r\nlast\r\n.\r\n"
".\r\n"
> EHLO client.test
greeting 220 test ESMTP
size 100000 tls false
SMTP: AUTH without TLS is refused: the password would cross the network in the clear (set cleartext_auth to send it so)
> AUTH PLAIN AHUAcA==
true
> MAIL FROM:<a@x.test> SIZE=194
> RCPT TO:<b@y.test>
> RCPT TO:<c@z.test>
> DATA
  | Date: Thu, 01 Jan 1970 00:00:00 +0000
  | From: a@x.test
  | To: b@y.test
  | Subject: hi
  | MIME-Version: 1.0
  | Content-Type: text/plain; charset="utf-8"
  | Content-Transfer-Encoding: 7bit
  | 
  | ..dot
  | end
true
> MAIL FROM:<a@x.test> SIZE=6
> RCPT TO:<no@y.test>
> RSET
SMTP: RCPT TO:<no@y.test> was refused: 550 no such user
> QUIT
true
true
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     smtp (loopback session on the tape, no heap)'
else
  echo "FAILED   smtp: $out"; status=1
fi
# std/mail on the caller tape: a message built and read back as a node
# array, addresses, dates, RFC 2231, encodings and errors; no heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/mail.ri 2>&1)
want='1020
ann@example.org,"bo b"@example.net
multipart/mixed
Grüße aus Köln
ann@example.org
Jörg Müller|jorg@example.com
bo b|Bob <"bo b"@example.net>
2
  multipart/mixed 2 7bit
  multipart/alternative 2 7bit
  text/plain 0 7bit
  text/html 0 7bit
  text/plain 0 base64
"Hallo Ann,\nbis bald.\n"
utf-8
bericht.txt attachment "line one\nline two\n"
8
message/rfc822 inner é
iso-8859-1 ab café café au lait
mail: the header section begins with a folded line
mail: line 1 of a header section is not a field: "bad line"
mail: a multipart/mixed part names no boundary
mail: a multipart/mixed body holds no line --q
mail: a multipart/mixed body ends before its closing line --q--
mail: the Content-Transfer-Encoding "x-uu" is not one std/mail reads
Wed, 31 Dec 1969 18:30:00 -0530
1057049557 120
1057071120 -240
"Subject: a very long subject line that has to be folded somewhere near the\r\n seventy-eighth column\r\n"
André Pirard
Ed Jones <c@a.test> | joe@where.test | x y <z@q.test>
mail: "two@a.test, three@b.test" holds 2 addresses, not one
"caf=C3=A9 =3D ok\r\n"
"café = ok\r\n"
"Y2Fmw6k=\r\n"
"prefix:Y2Fmw6kKbGluZSAJDQoAPQ==\r\n"
true
abc
true
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     mail (build and parse on the tape, no heap)'
else
  echo "FAILED   mail: $out"; status=1
fi
# std/png on the caller tape: Python-written files of every color type and
# depth decoded (RGBA CRC-32s from Python), encode round trips, refusals.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/png.ri 2>&1)
want='gray1 5x3 Gray 8 false 708e44d6 Comment=café bKGD
gray2_il 9x4 Gray 8 true 9780d096 Comment=café bKGD
gray16 4x4 Gray 16 false cd9a10fb Comment=café bKGD
rgb8_il 7x5 RGB 8 true 5a6c058b Comment=café bKGD
rgb16_trns 3x3 RGB 16 false d009b1b6 Comment=café bKGD
pal4 6x4 RGBA 8 false a44fbcbf Comment=café bKGD
ga8 3x2 GrayAlpha 8 false 0d9c74a6 Comment=café bKGD
rgba16_il 5x5 RGBA 16 true 0c6d4180 Comment=café bKGD
189 f6eaaf53 2 8 2718de15 
463 8eb00c4f 6 16 18776ee2 tEXt:Title=hä iTXt:Note=中
97 b865ba3b 0 8 87426669 
174 68f33a33 3 4 9c0fbb60 
true
true
605
png: not a PNG file: the 8-byte signature is not there
png: the IHDR chunk at offset 8 is cut short: it holds 13 bytes and the file has 10 after its header
png: the IHDR chunk at offset 8 fails its CRC-32: it says 0x6618313d, its bytes make 0xaf92d253
png: the file ends after 33 bytes, without an IEND chunk
png: the first chunk is IDAT; IHDR comes first
png: the image is 13x9, 117 pixels, past the limit of 100
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     png (decode and encode on the tape, no heap)'
else
  echo "FAILED   png: $out"; status=1
fi
# std/xz on the caller tape: Python lzma streams (checks, stored chunks,
# filters, .lzma, two streams) decoded whole and over an IO; refusals.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/xz.ri 2>&1)
want='crc64 5000 73131431 5000 73131431 2 true
crc32 5000 ef9a60e6 5000 ef9a60e6 2 true
sha256 5000 5e264c78 5000 5e264c78 2 true
none 5000 2ea5ffac 5000 2ea5ffac 2 true
stored 1500 f868003f 1500 f868003f 1 true
big 150000 3311c8f0 150000 3311c8f0 38 true
two 12 4ccb1bb3 12 4ccb1bb3 2 true
alone 4000 2cc2717c 4000 2cc2717c 2 true
delta 2048 9f5edd58 2048 9f5edd58 1 true
x86 1150 85d335ae 1150 85d335ae 1 true
magic xz: not an xz stream (the magic bytes are not FD 37 7A 58 5A 00)
cut xz: the stream ends inside its index
check xz: the index'\''s CRC32 does not match
trail xz: what follows the stream is neither padding nor another stream
pad xz: the stream padding is not a multiple of four bytes
xz: the block'\''s dictionary is 64 MiB, past the limit of 4 KiB
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     xz (decode whole and streamed on the tape, no heap)'
else
  echo "FAILED   xz: $out"; status=1
fi
# std/bzip2 on the caller tape: Python bz2 streams decoded whole and over
# an IO, text compressed and read back, refusals; no heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/bzip2.ri 2>&1)
want='l9 20000 471ad837 20000 471ad837 1 true
l1 250000 05e5edb5 250000 05e5edb5 9 true
random 800 38a5b19b 800 38a5b19b 1 true
two 12 4ccb1bb3 12 4ccb1bb3 2 true
one 1 e8b7be43 1 e8b7be43 1 true
1 104 2397efb5 true
9 104 8eea7bcb true
0
magic bzip2: not a bzip2 stream
cut bzip2: the stream ends inside a block
crc bzip2: block 2 starts with neither a block'\''s magic nor the end of the stream
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     bzip2 (decode and encode on the tape, no heap)'
else
  echo "FAILED   bzip2: $out"; status=1
fi
# std/tar on the caller tape: Python tarfile archives (pax, GNU, gzip,
# bzip2, xz) listed with data CRC-32s, written and read back; no heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/tar.ri 2>&1)
want='plain
  directory dir/ 0 00000000 - 755 
  regular file dir/hello.txt 300 25afb1de - 644 
  regular file dir/long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-.txt 1000 3b41c9e6 - 644 
  regular file café.bin 768 b0c0df2a - 644 ann
  symbolic link link 0 00000000 dir/hello.txt 644 
  regular file empty 0 00000000 - 644 
gnu
  directory dir/ 0 00000000 - 755 
  regular file dir/hello.txt 300 25afb1de - 644 
  regular file dir/long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-.txt 1000 3b41c9e6 - 644 
  regular file café.bin 768 b0c0df2a - 644 ann
  symbolic link link 0 00000000 dir/hello.txt 644 
  regular file empty 0 00000000 - 644 
gz
  directory dir/ 0 00000000 - 755 
  regular file dir/hello.txt 300 25afb1de - 644 
  regular file dir/long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-.txt 1000 3b41c9e6 - 644 
  regular file café.bin 768 b0c0df2a - 644 ann
  symbolic link link 0 00000000 dir/hello.txt 644 
  regular file empty 0 00000000 - 644 
bz2
  directory dir/ 0 00000000 - 755 
  regular file dir/hello.txt 300 25afb1de - 644 
  regular file dir/long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-.txt 1000 3b41c9e6 - 644 
  regular file café.bin 768 b0c0df2a - 644 ann
  symbolic link link 0 00000000 dir/hello.txt 644 
  regular file empty 0 00000000 - 644 
xz
  directory dir/ 0 00000000 - 755 
  regular file dir/hello.txt 300 25afb1de - 644 
  regular file dir/long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-long-name-.txt 1000 3b41c9e6 - 644 
  regular file café.bin 768 b0c0df2a - 644 ann
  symbolic link link 0 00000000 dir/hello.txt 644 
  regular file empty 0 00000000 - 644 
written false 10240 aac3f822
  directory d/ 0 00000000 - 755 
  regular file d/a.txt 600 984ca6bf - 644 
  regular file d/nnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnn 4 3b97a968 - 644 
  symbolic link s 0 00000000 d/a.txt 777 
written true 257 153ffa60
  directory d/ 0 00000000 - 755 
  regular file d/a.txt 600 984ca6bf - 644 
  regular file d/nnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnn 4 3b97a968 - 644 
  symbolic link s 0 00000000 d/a.txt 777 
tar: the header at offset 0 says checksum 3445, and its bytes sum to 3487: it is corrupt, or not a tar header
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     tar (read and write on the tape, no heap)'
else
  echo "FAILED   tar: $out"; status=1
fi
# std/zip on the caller tape: a Python zipfile archive (stored, deflate,
# bzip2, LZMA, Zstandard) read whole and streamed; written, read back.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/zip.ri 2>&1)
want='6 "a comment"
  stored.txt 0 3210 2adfe439 2adfe439
  deflate.txt 8 3211 89d3b5e6 89d3b5e6
  bzip2.txt 12 3209 853e0e5b 853e0e5b
  lzma.txt 14 3208 59285d70 59285d70
  zstd.txt 93 3208 9a5dfc2c 9a5dfc2c
  dir/café.txt 8 0 00000000 00000000
written 582
5 "made here"
  a.txt 8 1800 81f70778 81f70778
  b.bin 0 0 00000000 00000000
  c.bz2 12 1500 d5e2fd11 d5e2fd11
  d.zst 93 1800 f75c6d45 f75c6d45
  dir/eé.txt 8 5 c443d071 c443d071
6 "a comment"
  stored.txt zip: "stored.txt"'\''s CRC-32 is 38536260, and the central directory says 2adfe439
  deflate.txt 8 3211 89d3b5e6 89d3b5e6
  bzip2.txt 12 3209 853e0e5b 853e0e5b
  lzma.txt 14 3208 59285d70 59285d70
  zstd.txt 93 3208 9a5dfc2c 9a5dfc2c
  dir/café.txt 8 0 00000000 00000000
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     zip (read and write on the tape, no heap)'
else
  echo "FAILED   zip: $out"; status=1
fi
# std/dns on the caller tape: wire bytes made by Python, compression
# pointers and a loop of them, an HTTPS record, a loopback resolver over
# UDP and, for a truncated answer, TCP.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/dns.ri 2>&1)
want='true
128 beef0100000100000000000103777777076578616d706c6503636f6d000041000100002904d0000000000054000c0050
48879
4660 true www.example.com 1 rcode 16 4 ends true
true
false
  www.example.com 5 300 17 cdn.example.net
  cdn.example.net 1 60 4 
  cdn.example.net 1 60 4 
  www.example.com 16 30 13 
192.0.2.7,192.0.2.8 at cdn.example.net after 1
hello| world
true the answer was malformed: the question'\''s name
the answer was malformed: 2 bytes, shorter than a header
1 . alpn="h2,h3" port=8443 ipv4hint=192.0.2.1 ech=AAQBAgME ipv6hint=2001:db8::1
svc.example 8443 h2,h3 6
the answer was malformed: SvcParamKey port: 1 bytes, where a port is 2
db.corp.test db.test db
a.b
udp www.example.test 1
udp www.example.test 28
198.51.100.7 2001:db8::53
udp big.example.test 1
tcp big.example.test 1
udp big.example.test 28
192.0.2.99
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     dns (messages and a loopback resolver on the tape, no heap)'
else
  echo "FAILED   dns: $out"; status=1
fi
# std/secure_dns over loopback: DoT, then DoH by POST and GET, against
# bench/std_secure_dns_server.py; the upstreams connect by address, so no
# exchange calls back into the resolver (SPEC 3.5).
if python3 -c 'import ssl; from cryptography import x509' 2>/dev/null; then
  srv=$(mktemp -d)
  python3 bench/std_secure_dns_server.py "$srv" >"$srv/log" 2>&1 &
  srv_pid=$!
  for _ in $(seq 200); do [ -f "$srv/ready" ] && break; sleep 0.1; done
  out=$(RIS_HEAP_STATS=1 timeout 300 "$RIS" run test/ris/secure_dns.ri -- \
    "$srv" 2>&1)
  kill "$srv_pid" 2>/dev/null; wait "$srv_pid" 2>/dev/null
  rm -rf "$srv"
  want='a.zone.test 192.0.2.1
dual.zone.test 192.0.2.2 2001:db8::2
dot connections 1
a.zone.test 192.0.2.1
six.zone.test 2001:db8::6
post connections 1 reused 3
dual.zone.test 192.0.2.2 2001:db8::2
missing.zone.test failed: not found true
alias.zone.test 192.0.2.1
ris heap: 0 allocations, 0 bytes'
  if [ "$out" = "$want" ]; then
    echo 'runs     secure_dns (DoT and DoH on loopback, no heap)'
  else
    echo "FAILED   secure_dns: $out"; status=1
  fi
else
  echo 'skipped  secure_dns (no python3 cryptography)'
fi
# std/regex on the caller tape: groups, alternation, counts, anchors,
# classes, no match and a long text, with nothing on the heap.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/regex.ri 2>&1)
want='bbbc
2026-10-30 2026 10 30 3-13
dog,cat,bird
a
xababy
oo,ooo,ooo
true
false
word
ff,0,1A,C0DE
CD,12
a|b|c
HeLLo
none
1-2
40000-40008
40001
a#b#c#
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     regex (Pike VM on tape Arrays, no heap)'
else
  echo "FAILED   regex: $out"; status=1
fi
# std/string_scanner reads tokens through std/regex.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/regex_scanner.ri 2>&1)
want='w:let w:x p:= n:42:42 p:;
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     regex_scanner (StringScanner over Regex, no heap)'
else
  echo "FAILED   regex_scanner: $out"; status=1
fi
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

# Every def, loop round and block frees (SPEC 1.1): 1,000,000 rounds
# reading `a.first`, in a loop and a def's loop, and calling a def that
# makes a fresh String, keep resident memory and mappings flat.
out=$(timeout 300 "$RIS" run test/ris/scope_frees.ri 2>&1)
if [ "$?" = 0 ] && [ "$(grep -c '^PASS: ' <<<"$out")" = 3 ]; then
  echo "runs     scope_frees (1,000,000 rounds, flat RSS and mappings)"
else
  echo "FAILED   scope_frees: $out"; status=1
fi

# A one-call def hands its caller's destination on (SPEC 1.5, 1.9):
# File.read's result is neither copied nor moved down.
out=$(RIS_TAPE_STATS=1 "$RIS" run test/ris/scope_result_read.ri 2>&1)
if [ "$?" = 0 ] && grep -qxF 'true' <<<"$out" &&
   grep -qF 'ris tape results: 0 moved down (0 bytes)' <<<"$out"; then
  echo "runs     scope_result_read (File.read wrapper, no result copy)"
else
  echo "FAILED   scope_result_read: $out"; status=1
fi

# 10,000 fresh results each move down once, not staged and copied back;
# 64 KiB of per-call scratch is freed; borrowed input stays a view.
out=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 "$RIS" run \
  test/ris/pending_result.ri 2>&1)
if [ "$?" = 0 ] &&
   grep -qF 'PASS: pending results and borrowed views' <<<"$out" &&
   grep -qF 'ris heap: 0 allocations, 0 bytes' <<<"$out" &&
   grep -qF 'ris tape results: 10000 moved down' <<<"$out" &&
   grep -qF '2 scopes, 5 mappings made, 0 unmapped, 0 tapes grown' <<<"$out"; then
  echo "runs     pending_result (results moved down, borrowed stay views)"
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
            semantic_version uuid const_int_width; do
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

# The URI class (to_uri of a parse) keeps its fields through normalize.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/uri_legacy.ri 2>&1)
if [ "$?" -eq 0 ] && grep -qxF 'URI: legacy wrappers' <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out"; then
  echo "runs     uri_legacy (URI class normalize, zero heap)"
else
  echo "FAILED   uri_legacy: $out"; status=1
fi

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
# SPEC 3.2: a tape block's data kept by a call into an object from
# outside it, here and through a server handler's field.
expect tape_block_store_call 'cannot store data made in this tape block'
expect tape_block_handler_store 'cannot store data made in this tape block'
# The refusal points at the handler's own store, naming std's call.
out=$("$RIS" build --no-codegen test/ris/refused/tape_block_handler_store.ri 2>&1)
if grep -qF 'tape_block_handler_store.ri:13:5' <<<"$out" &&
   grep -qF 'This store runs inside the tape block of the call at' <<<"$out"; then
  echo "refused  tape_block_handler_store (at the handler's line)"
else
  echo "FAILED   tape_block_handler_store line: $out"; status=1
fi
# What a tape block may still do; its scratch is freed when it ends.
out=$(RIS_TAPE_STATS=1 "$RIS" run test/ris/tape_block_reset.ri 2>&1)
code=$?
mappings=$(sed -n \
  's/^ris tape:.*scopes, \([0-9]*\) mappings made.*/\1/p' <<<"$out")
if [ "$code" -eq 0 ] && grep -qxF '4 k3 3890' <<<"$out" &&
    [ -n "$mappings" ] && [ "$mappings" -le 16 ]; then
  echo "runs     tape_block_reset (block scratch freed)"
else
  echo "FAILED   tape_block_reset: $out"; status=1
fi
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
for rule in plain_build plain_build_inline io_parameter array_refill; do
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
# fix leaves alone a refill it cannot prove: a new Array that is not empty.
kept=$(f="${TMPDIR:-/tmp}/fix_array_refill_kept.ri";
  cp test/ris/fix/array_refill_kept.ri "$f" &&
  { "$RIS" fix "$f" >/dev/null 2>&1; diff -q test/ris/fix/array_refill_kept.ri "$f"; })
if [ "$?" -eq 0 ]; then echo "runs     fix array_refill_kept"; else echo "FAILED   fix array_refill_kept: $kept"; status=1; fi
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
# Repeated joined groups must reuse task and request tape storage: the
# mappings stay bounded (about 38 Arrays live at startup, each its own
# side reservation, plus the tapes), not one per request.
out=$(RIS_HEAP_STATS=1 RIS_TAPE_STATS=1 "$RIS" run --release \
  test/ris/server_groups.ri 2>&1)
code=$?
mappings=$(sed -n \
  's/^ris tape:.*scopes, \([0-9]*\) mappings made.*/\1/p' <<<"$out")
if [ "$code" -eq 0 ] &&
    grep -qxF 'PASS: server groups' <<<"$out" &&
    grep -qxF 'ris heap: 0 allocations, 0 bytes' <<<"$out" &&
    [ -n "$mappings" ] && [ "$mappings" -le 64 ] &&
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
    grep -qxF 'array: 0' <<<"$out"; then
  echo "census   heap_fields (initializer's Array is on the tape)"
else
  echo "FAILED   heap_fields: $out"
  status=1
fi
out=$("$RIS" heap --user test/ris/heap_kinds.ri 2>&1)
if [ "$?" -eq 0 ] && ! grep -qE '^class: [1-9]' <<<"$out" &&
    grep -qxF 'string: 0' <<<"$out" && grep -qxF 'array: 0' <<<"$out" &&
    grep -qxF 'hash: 0' <<<"$out" && grep -qxF 'closure: 1' <<<"$out"; then
  # String, Array and Hash are tape types: only the closure counts.
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
expect program_threads 'program tape writes require a single kernel thread'
expect program_field_thread \
  'program tape writes require a single kernel thread'
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

# std/password: scrypt RFC 7914 vectors, an OpenBSD bcrypt vector.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/password.ri 2>&1)
want='77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906
fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b3731622eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640
true
false
60 $2b$04$ true
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     password (scrypt and bcrypt on the tape, no heap)'
else
  echo "FAILED   password: $out"; status=1
fi

# std/string_pool: interning on the tape and a rehash.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/string_pool.ri 2>&1)
want='alpha alpha 1 8
true
41 64 word7 true
true
42
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     string_pool (interned strings on the tape, no heap)'
else
  echo "FAILED   string_pool: $out"; status=1
fi

# std/deque: a ring in a tape Array, growth while wrapped, rotation.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/deque.ri 2>&1)
want='Deque{1, 2, 3, 4} 4
Deque{3, 4, 5, 6} 4
Deque{3, 4, 5, 6, 7} 8
Deque{-1, 0, 1, 2, 3, 4, 5, 6, 7} 16
Deque{2, 3, 4, 5, 6, 7, -1, 0, 1}
6 Deque{2, 3, 100, 4, 5, 7, -1, 0, 1}
1 2 7 3 0
s9 s0 10 16
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     deque (ring buffer on the tape, no heap)'
else
  echo "FAILED   deque: $out"; status=1
fi

# std/slice: Slice#dup on the caller tape.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/slice_dup.ri 2>&1)
want='10 99 4 30
true 7
0
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     slice_dup (Slice#dup on the tape, no heap)'
else
  echo "FAILED   slice_dup: $out"; status=1
fi

# std/system: the affinity mask read into a tape Array (three CPUs under
# taskset), /proc/self/auxv and /sys read into a builder.
out=$(RIS_HEAP_STATS=1 taskset -c 0-2 "$RIS" run test/ris/system.ri 2>&1)
want='3
4096
false
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     system (affinity and /proc on the tape, no heap)'
else
  echo "FAILED   system: $out"; status=1
fi

# std/format: sprintf only on the tape (the heap overloads gone).
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/format.ri 2>&1)
want='PASS: format on the tape
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     format (sprintf on the tape, no heap)'
else
  echo "FAILED   format: $out"; status=1
fi

# std/eiy: templates compiled on the caller tape (heap wrappers gone).
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/eiy.ri 2>&1)
want='PASS: eiy on the tape
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     eiy (templates on the tape, no heap)'
else
  echo "FAILED   eiy: $out"; status=1
fi

# std/log: AsyncBackend posts lines to a writer task (RisBoard).
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/log_async.ri 2>&1)
want='line 0
line 50
line 100
line 150
after
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     log_async (writer task on the board, no heap)'
else
  echo "FAILED   log_async: $out"; status=1
fi

# std/xml XPath (RisXPath) on the XmlTree node array, checked against
# xml.etree.
out=$(RIS_HEAP_STATS=1 "$RIS" run test/ris/xpath.ri 2>&1)
want='item=1 item=2
item=1 item=2 item=3 item=4
item=1 item=3 item=4
item=2
item=2 item=4
item=2 item=4
0
item=1 item=2 group
item=2
bee
1,2,3,4
twothree
1
item=3
item=4
b
group
0
XPath: an empty path
XPath: "/root/" ends after a '\''/'\'', where a step goes
XPath: position 0 at 7: positions start at 1
XPath: "child::a" at 1 names an axis, which is not read: use a step, // or ..
XPath: "a + b" at 0 is not a name (axes and functions are not read)
XPath: the predicate [@k=x] at 6 is not read: [n], [last()], [@a] or [@a='\''v'\'']
XPath: @n must be the last step
XPath: a '\''['\'' at 3 with no '\'']'\''
ris heap: 0 allocations, 0 bytes'
if [ "$out" = "$want" ]; then
  echo 'runs     xpath (XPath on the node array, no heap)'
else
  echo "FAILED   xpath: $out"; status=1
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
