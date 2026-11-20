#!/usr/bin/env bash
# The prelude's collections at their edges: `Array`, `Hash` and `Set`.
#
#     bash test/cli/collections_exercise.sh
#
# `test/cli/collections_exercise.ri` is the program, run plain and optimised.
# Then the panics an empty receiver answers with are driven here - a
# panicking program has no next line to assert on - and then each check is
# proved capable of failing by patching a *copy of the prelude* and building
# against it through `RIS_PATH`. A check that cannot fail is not a check.
#
# The defect this gate was written for: `a.concat(a)`. `each` walked
# *other*'s size while `<<` grew it, so appending an array to itself never
# reached the end; it grew the buffer until the capacity arithmetic
# overflowed, and `[1, 2].concat(itself)` died of "arithmetic overflow".
#
# 0.18 added what a program asks of the two beyond that: an array's spans by
# start and count and by range (either end negative, endless, beginless,
# past the end), setting and truncating them, `push`, `unshift`, `pop?`,
# `first?`, `last(n)`, `flatten`, `transpose`, `-`, `&`, `|`, `*` and `uniq`
# by a key; a table's `fetch`, `dig`, `merge`, `update`, transforms,
# `select`/`reject` and their in-place forms, `shift`, `put_if_absent`,
# `clear`, `dup`, the block questions, and `==` and `hash` over its pairs in
# any order. Each section has its refusal driven below and a patch that
# breaks it.
#
# Exits non-zero if any check fails or if any patch leaves the exercise green.

set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
# the wrapper in bin is a posix shell script, so a caller that already has a
# compiler of its own names it through the environment.
RIS="${RIS:-$REPO/bin/ris}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ris-collections.XXXXXX")"

# A native compiler cannot resolve this shell's own path mapping: a search
# path built from the shell's `pwd` finds no prelude at all, and a scratch
# directory named `/tmp/tmp.X` is silently ignored on that path, so the
# patched copy is never read and the proof that a check can fail quietly
# stops proving it.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT)
    REPO="$(cygpath -m "$REPO")"
    WORK="$(cygpath -m "$WORK")"
    ;;
esac

# The search path is a list, and the byte between its entries is the
# platform's: `;` where a drive letter already owns the colon.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT) PSEP=';' ;;
  *) PSEP=':' ;;
esac

trap 'rm -rf "$WORK"' EXIT

status=0

run_case() { # run_case <label> <name> [build flags...]
  local label="$1" name="$2"
  shift 2
  if ! "$RIS" build "$@" -o "$WORK/$name" "$REPO/test/cli/collections_exercise.ri" \
       > "$WORK/$name.build" 2>&1; then
    echo "  $label: the exercise did not build"
    sed -n '1,12p' "$WORK/$name.build"
    status=1
    return
  fi
  if ! "$WORK/$name" > "$WORK/$name.out" 2>&1; then
    echo "  $label: the exercise panicked"
    tail -3 "$WORK/$name.out"
    status=1
    return
  fi
  if ! grep -q "all collection checks passed" "$WORK/$name.out"; then
    echo "  $label: the exercise ended without passing"
    tail -3 "$WORK/$name.out"
    status=1
    return
  fi
  echo "  $label: every check held"
}

echo "== the collections, plain"
run_case "plain" plain

echo
echo "== and with optimisation on (--release)"
run_case "release" release --release

echo
echo "== an empty receiver, which is a panic with a name on it"

panics_with() { # panics_with <label> <name> <phrase> <expression>
  local label="$1" name="$2" phrase="$3" expression="$4"
  printf 'module main\n\nputs (%s).to_s\n' "$expression" > "$WORK/$name.ri"
  if ! "$RIS" build -o "$WORK/$name" "$WORK/$name.ri" > "$WORK/$name.build" 2>&1; then
    echo "  $label: the program did not build"
    sed -n '1,10p' "$WORK/$name.build"
    status=1
    return
  fi
  "$WORK/$name" > "$WORK/$name.out" 2>&1
  local code=$?
  if [ "$code" -eq 0 ]; then
    echo "  $label: it answered instead of panicking"
    status=1
    return
  fi
  if [ "$code" -ne 1 ]; then
    echo "  $label: died with exit $code rather than a panic"
    tail -2 "$WORK/$name.out"
    status=1
    return
  fi
  if ! grep -q "$phrase" "$WORK/$name.out"; then
    echo "  $label: panicked, but not with '$phrase'"
    tail -2 "$WORK/$name.out"
    status=1
    return
  fi
  printf '  %s: exits 1 at "%s"\n' "$label" "$(grep -m1 -o "$phrase.*" "$WORK/$name.out")"
}

panics_with "pop of an empty array" pop_empty "pop of an empty array" "([] of Int32).pop"
panics_with "shift of an empty array" shift_empty "shift of an empty array" "([] of Int32).shift"
panics_with "first of an empty array" first_empty "first of an empty array" "([] of Int32).first"
panics_with "last of an empty array" last_empty "Array#last: empty" "([] of Int32).last"
panics_with "an index past the end" index_past "out of range for 2 elements" "[1, 2][5]"
panics_with "an index before the start" index_before "out of range for 2 elements" "[1, 2][-5]"
panics_with "a key nobody put in" missing_key "no such key" "({} of Int32 => Int32)[5]"
panics_with "a negative count" negative_count "negative count" "[1, 2].first(-1).size"
# A zip with a shorter array is refused, as the other library refuses it:
# the pairs stopped at the shorter, and the third element went unsaid.
panics_with "a zip with a shorter array" zip_shorter "index 2 out of range for 2 elements" "[1, 2, 3].zip([4, 5]).size"
panics_with "a block zip with a shorter array" zip_block_shorter "index 2 out of range for 2 elements" "[1, 2, 3].zip([4, 5]) { |a, b| a + b }"
# The spans and the 0.18 tables refuse what has no answer, each with a
# sentence that names what was asked.
panics_with "a span starting past the end" span_past "array view out of bounds" "[1, 2, 3][4, 1]"
panics_with "a range starting past the end" range_past "array range out of bounds" "[1, 2, 3][4..]"
panics_with "a range starting before the start" range_before "array range out of bounds" "[1, 2, 3][-4..-1]"
panics_with "a span set past the end" set_past "array replacement out of bounds" "[1, 2, 3][5, 0] = 9"
panics_with "a repeat a negative number of times" repeat_negative "negative count: -2" "[1] * -2"
panics_with "the last of a negative count" last_negative "negative count: -1" "[1].last(-1)"
panics_with "rows of unequal size" ragged "transpose of rows of unequal size: row 1 has 1 elements, row 0 has 2" "[[1, 2], [3]].transpose"
panics_with "a value no key has" no_key_for "no key for the value 2" "{\"a\" => 1}.key_for(2)"
panics_with "a shift of an empty table" hash_shift_empty "shift of an empty hash" "({} of String => Int32).shift"
panics_with "the first key of an empty table" first_key_empty "first_key of an empty hash" "({} of String => Int32).first_key"
panics_with "an update of a missing key" update_missing "no such key \"b\"" "{\"a\" => 1}.update(\"b\") { |v| v }"
panics_with "a dig past a value" dig_past "the value at \"a\" is not a table to dig into" "{\"a\" => 1}.dig(\"a\", \"b\")"
panics_with "a dig of a missing key" dig_missing "no such key \"q\"" "{\"a\" => 1}.dig(\"q\", \"b\")"
panics_with "values_at of a missing key" values_at_missing "no such key \"z\"" "{\"a\" => 1}.values_at(\"a\", \"z\")"

echo
echo "== proving the checks can fail, one broken method at a time"

# A copy of the whole prelude with one method patched, on `RIS_PATH` ahead of
# the real one. The patch has to change the file - a sed that matched nothing
# would otherwise read as a pass - and the exercise then has to exit non-zero
# at the check that names the method.
prove_fails() { # prove_fails <label> <dir> <file> <phrase> <sed script>
  local label="$1" dir="$2" file="$3" phrase="$4" script="$5"
  mkdir -p "$WORK/$dir/ris"
  cp -R "$REPO/src/ris/." "$WORK/$dir/ris/"
  sed -e "$script" "$REPO/src/ris/$file" > "$WORK/$dir/ris/$file"
  if cmp -s "$REPO/src/ris/$file" "$WORK/$dir/ris/$file"; then
    echo "  $label: the patch changed nothing, so this proves nothing"
    status=1
    return
  fi

  if ! RIS_PATH="$WORK/$dir${PSEP}$REPO/src" "$RIS" build \
       -o "$WORK/$dir/program" "$REPO/test/cli/collections_exercise.ri" \
       > "$WORK/$dir/build" 2>&1; then
    echo "  $label: the patched prelude did not build"
    sed -n '1,10p' "$WORK/$dir/build"
    status=1
    return
  fi

  # A patch can also hang the exercise - the defect this gate was written
  # for did exactly that until the arithmetic caught it - so the run is
  # given a bound.
  timeout 20 "$WORK/$dir/program" > "$WORK/$dir/out" 2>&1
  local code=$?
  if [ "$code" -eq 0 ]; then
    echo "  $label: the exercise still passed, so it does not test this"
    status=1
    return
  fi
  if [ "$code" -eq 124 ]; then
    printf '  %s: the exercise stopped answering (timed out)\n' "$label"
    return
  fi
  if ! grep -q "$phrase" "$WORK/$dir/out"; then
    echo "  $label: failed, but not at the expected check (wanted '$phrase')"
    tail -2 "$WORK/$dir/out"
    status=1
    return
  fi
  printf '  %s: exits %s at "%s"\n' "$label" "$code" \
    "$(grep -m1 -o "$phrase.*" "$WORK/$dir/out" | sed 's/^assert failed: //')"
}

# Mutate the current tape implementations, one method at a time.
# Dense deletion has no tombstones or front cursor to mutate.
# Large queue and set workloads live in test/speed/.

prove_fails 'a default is ignored' no_default hash_tape.ri \
  'no such key "z"' \
  's/^      if default = @default$/      if default = nil/'

prove_fails 'the fill form fills nothing' no_fill tape.ri \
  'array: filled has the size asked' \
  's/^    Array(T).new(count) { |index| value }$/    Array(T).new(0)/'

prove_fails 'concat reads a growing size' grow_concat tape.ri \
  'array: concat with itself doubles' \
  's/^    taking = other.size$/    taking = 1/'

prove_fails 'a sort that compares every pair' quadratic_sort tape.ri \
  'array: a sort of 100,000 made' \
  's/start + 16 < count ? start + 16 : count/count/'

prove_fails 'a merge that takes the right run on a tie' unstable_sort tape.ri \
  'array: a sort is ascending and keeps equal elements in order' \
  's/(yield from\[left\], from\[right\]) <= 0/(yield from[left], from[right]) < 0/'

prove_fails 'a sort that asks == after <' two_question_sort tape.ri \
  'array: sorted asks one question a step' \
  's/^    sort_in_place { |a, b| b < a ? 1 : 0 }$/    sort_in_place { |a, b| a < b ? -1 : (a == b ? 0 : 1) }/'

prove_fails 'a key sort that asks < both ways' two_way_key_sort tape.ri \
  'array: sorted_by asks < as often as sorted' \
  's/keys.unchecked(b) < keys.unchecked(a) ? 1 : 0/keys.unchecked(a) < keys.unchecked(b) ? -1 : (keys.unchecked(b) < keys.unchecked(a) ? 1 : 0)/'

prove_fails 'an Int64 hashed by its type' int64_type_hash number.ri \
  'hash: Int64 keys spread' \
  '/^struct Int64$/,/^end$/{/^  def hash : Int32$/,/^  end$/d;}'

prove_fails 'an instance that is not itself' no_identity primitives.ri \
  'reference: an instance equals itself' \
  '/^class Reference$/,/^end$/{/^  def ==(other : Reference) : Bool$/,/^  end$/d;}'

prove_fails 'instances hashed by their type' type_hash primitives.ri \
  'reference: instances hash apart' \
  's/^      (object_id.unsafe_shr(4_u64) ^ object_id.unsafe_shr(36_u64)).unsafe_to_i32$/      crystal_type_id/'

prove_fails 'a rewritten key appends' double_write hash_tape.ri \
  'hash: a key written twice is one entry' \
  's/^    index = find(key)$/    index = -1/'

prove_fails 'a set forgets its members' dup_set set.ri \
  'set: the other one is still in' \
  's/^  def includes?(value : T) : Bool$/  def includes?(value : T) : Bool\n    return false/'

prove_fails 'a negative index does not wrap' no_wrap tape.ri \
  'out of range for 3 elements' \
  '/^      index = index &+ count$/d'

prove_fails 'uniq keeps everything' no_uniq tape_api.ri \
  'array: uniq' \
  '/^  def uniq : Array(T)$/,/^  end$/{/^      next if seen.has_key?(value)$/d;}'

prove_fails 'pop does not shrink' no_shrink tape.ri \
  'array: five hundred pops' \
  's/^    __remove_slot(size - 1)$/    self[size - 1]/'

prove_fails 'the range walk steps past its end' past_end range.ri \
  'arithmetic overflow' \
  's/^    yield value if !@exclusive \&\& value == @end$/    yield value if !@exclusive \&\& value <= @end \&\& (value = value + 1) < 0/'

prove_fails 'a tuple hash that barely mixes' weak_tuple object.ri \
  'hash: a 300 by 300 grid of tuples spreads' \
  's/^      value = (value ^ self\[{{i}}\].hash.to_i64.unsafe_to_u64) \&\* 0x100000001B3_u64$/      value = (value \&* 31_u64) \&+ self[{{i}}].hash.to_i64.unsafe_to_u64/; /^      value = value ^ value.unsafe_shr(29_u64)$/d'

prove_fails 'an array hashed by its type' type_hashed_array tape_api.ri \
  'hash: a 300 by 300 grid of arrays spreads' \
  's/^    value.hash$/    crystal_type_id/'

prove_fails 'max_by passes over a NaN key' nan_max_by tape.ri \
  'array: max_by of a NaN key is the NaN' \
  's/^      if best_key < key || (key.is_a?(Float) \&\& key != key \&\& best_key == best_key)$/      if best_key < key/'

prove_fails 'an inclusive range drops its end' inclusive_end tape_api.ri \
  'array: an inclusive range keeps its end' \
  's/^      stop += 1$/      stop += 0/'

prove_fails 'a start at the end is refused' start_at_end tape_api.ri \
  'array: a start at the end is the empty tail, for \[\]? too' \
  '/private def api_span?/,/^  end$/s/start > size/start >= size/'

prove_fails 'a range start at the end is refused' range_at_end tape_api.ri \
  'array: a range starting at the end is empty' \
  '/private def api_range?/,/^  end$/s/start > size/start >= size/'

prove_fails 'a span set from itself is read as it moves' self_splice tape_api.ri \
  'array: a span set from itself reads a copy' \
  's/^    source = values.dup$/    source = values/'

prove_fails 'a shorter span leaves the gap' open_gap tape_api.ri \
  'array: a span set to one value' \
  's/^    concat(tail)$/    concat(source)/'

prove_fails 'truncate keeps the front' truncate_front tape_api.ri \
  'array: truncate keeps the span' \
  '/^    span\[0\].times { shift }$/d'

prove_fails 'push of several keeps the last' push_last tape_api.ri \
  'array: push one and several' \
  's/^      push(values\[i\])$/      push(values[values.size - 1])/'

prove_fails 'unshift appends' unshift_back tape_core.ri \
  'array: unshift one and several' \
  '/def unshift(value : T)/,/^  end$/s/^    i = size - 1$/    i = 0/'

prove_fails 'pop? answers nothing' pop_nothing tape.ri \
  'array: pop? answers the last' \
  's/^    empty? ? nil : pop$/    nil/'

prove_fails 'first? answers nothing' first_nothing tape.ri \
  'array: first? answers the first' \
  's/^    empty? ? nil : unsafe_at(0)$/    nil/'

prove_fails 'last n is the first n' last_first tape_api.ri \
  'array: last n' \
  's/^    start = size - count$/    start = 0/'

prove_fails 'flatten stops a level down' shallow_flatten tape_api.ri \
  'array: flatten goes all the way down' \
  's/^      value.each { |inner| flatten_into(result, inner) }$/      value.each { |inner| flatten_into(result, inner) unless inner.is_a?(Array) }/'

prove_fails 'transpose repeats the first column' first_column tape_api.ri \
  'array: transpose' \
  's/^      each { |row| line << row\[column\] }$/      each { |row| line << row[0] }/'

prove_fails '- removes nothing' minus_short tape_api.ri \
  'array: - keeps duplicates and order' \
  's/^      each { |value| result << value unless other.includes?(value) }$/      each { |value| result << value }/'

prove_fails '- against a long array removes nothing' minus_long tape_api.ri \
  'array: - against a long array' \
  's/^      each { |value| result << value unless present.has_key?(value) }$/      each { |value| result << value }/'

prove_fails '& keeps duplicates' and_twice tape_api.ri \
  'array: & keeps each once' \
  '/^      present.delete(value)$/d'

prove_fails '| keeps duplicates' or_twice tape_api.ri \
  'array: | keeps each once' \
  '/^  def |(other : Array(U)) : Array(T | U) forall U$/,/^  end$/{/^      next if seen.has_key?(value)$/d;}'

prove_fails '* repeats once' repeat_once tape_api.ri \
  'array: \* repeats' \
  's/^    while round < times$/    while round < 1/'

prove_fails 'uniq by a key keeps everything' uniq_key tape_api.ri \
  'array: uniq by a key keeps the first of each' \
  '/^  def uniq(& : T -> U) : Array(T) forall U$/,/^  end$/{/^      next if seen.has_key?(key)$/d;}'

prove_fails 'fetch answers the default' fetch_default hash_tape.ri \
  'hash: fetch answers the value' \
  's/^    index < 0 ? default : @values\[index\]$/    default/'

prove_fails 'dig? returns nothing' dig_shallow tape_api.ri \
  'hash: dig? reads one key' \
  '/^  def dig?(key : K)$/, /^  end$/s/^    self\[key\]?$/    nil/'

prove_fails 'merge keeps the first value' merge_first tape_api.ri \
  'hash: merge, the second value wins' \
  's/^    other.each { |key, value| self\[key\] = value }$/    other.each { |key, value| self[key] = value unless has_key?(key) }/'

prove_fails 'merge'"'"'s block is not asked' merge_block tape_api.ri \
  'hash: merge with a block' \
  's/^      self\[key\] = has_key?(key) ? (yield key, self\[key\], value) : value$/      self[key] = value/'

prove_fails 'update answers the new value' update_new tape_api.ri \
  'hash: update answers the old value' \
  '/def update(key : K/,/^  end$/s/^    old$/    self[key]/'

prove_fails 'the entry walk skips the oldest' entry_walk hash_tape.ri \
  'hash: each counts what size says' \
  '/def each(\& : K, V -> Nil)/,/^  end$/s/^    i = 0$/    i = 1/'

prove_fails 'select_in_place rejects' select_rejects tape_api.ri \
  'hash: select_in_place keeps' \
  's/^    reject_in_place { |key, value| !(yield key, value) }$/    reject_in_place { |key, value| yield key, value }/'

prove_fails 'key_for answers another key' key_for_other tape_api.ri \
  'hash: key_for' \
  's/^    each { |key, stored| return key if stored == value }$/    each { |key, stored| return key if stored != value }/'

prove_fails 'compact keeps nothing' compact_nothing tape_api.ri \
  'hash: compact keeps the values' \
  's/^      result\[key\] = value unless value.nil?$/      result[key] = value if false \&\& !value.nil?/'

prove_fails 'count counts every pair' count_all tape_core.ri \
  'hash: count' \
  's/^    each { |k, v| n += 1 if yield k, v }$/    each { |k, v| n += 1 }/'

prove_fails 'first_key? reads a deleted entry' first_key_gone tape_api.ri \
  'hash: first_key?' \
  '/def first_key? : K?/,/^  end$/s/^    each { |key, value| return key }$/    return nil/'

prove_fails 'shift leaves the pair in' shift_keeps tape_api.ri \
  'hash: shift takes the oldest out' \
  's/^      kept_value = delete(key)$/      kept_value = self[key]/'

prove_fails 'values_at repeats the first' values_at_first tape_api.ri \
  'hash: values_at in the order asked' \
  's/^      result << self\[keys\[at\]\]$/      result << self[keys[0]]/'

prove_fails 'put_if_absent overwrites' put_overwrites tape_api.ri \
  'hash: put_if_absent keeps what is there' \
  '/^    return self\[key\] if has_key?(key)$/d'

prove_fails 'delete'"'"'s block is always asked' delete_block tape_api.ri \
  'hash: delete with a block answers the value' \
  's/^    return yield key unless has_key?(key)$/    return yield key/'

prove_fails 'clear keeps its count' clear_count hash_tape.ri \
  'hash: clear empties' \
  '/def clear : self/,/^  end$/{/^    @head\[0\] = 0$/d;}'

prove_fails 'dup drops the default' dup_default tape_core.ri \
  'no such key "missing"' \
  '/def dup : self/,/^  end$/s/^    Tape.owner_copy(self, RisCurrentTape.new)$/    result = self.class.new; each { |key, value| result[key] = value }; result/'

prove_fails '== reads only the keys' keys_only tape_api.ri \
  'hash: a different value is unequal' \
  's/^      return false unless other.has_key?(key) \&\& other\[key\] == value$/      return false unless other.has_key?(key)/'

prove_fails 'a table hash that counts the order' ordered_hash tape_api.ri \
  'hash: equal tables hash alike' \
  's/^      total = total \&+ (pair ^ pair.unsafe_shr(29_u64))$/      total = (total \&* 31_u64) \&+ (pair ^ pair.unsafe_shr(29_u64))/'

prove_fails '== is identity again' identity_eq tape_api.ri \
  'hash: equal pairs in another order are equal' \
  '/^  def ==(other : Hash(K, V)) : Bool$/,/^  end$/d'

echo
echo "== and what an empty receiver says when it is asked for a size"
panics_with "a negative capacity" neg_cap "tape bad size: -1" "Array(Int32).new(-1).size"

echo
if [ "$status" -eq 0 ]; then
  echo "Collections: a key is one entry however often it is written, a delete"
  echo "leaves the rest findable, a crowded slot is still searched, an array"
  echo "appended to itself doubles, spans and table questions answer at their"
  echo "edges, equal tables are equal in any order, and an empty receiver"
  echo "panics with a name."
else
  echo "the collection surface does not hold"
fi
exit "$status"
