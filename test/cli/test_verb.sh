#!/usr/bin/env bash
# Drives `iyi test` — the verify loop with no framework (AI_FIRST.md §2 #4).
#
#     bash test/cli/test_verb.sh
#
# A test is a plain iyi program that exits non-zero to fail. Four steps,
# and every one is a failure proof of a different kind, because a test
# runner's whole job is telling the four verdicts apart:
#
#   1. Passing tests: exit 0, and `--json` reports them as data.
#   2. A failing test: exit 1, the file named, its own output shown.
#   3. A test that does not build: a failure that says so, not a crash.
#   4. A test that hangs: killed at the deadline and named, because a
#      harness that can hang is not a harness.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
# The compiler, overridable: `bin/ris` is a POSIX shell wrapper, and on
# Windows the caller is the only one who knows where the real binary is.
RIS="${RIS:-$REPO/bin/ris}"
mkdir -p "$REPO/test/cli/.work"
WORK="$(mktemp -d "$REPO/test/cli/.work/XXXXXX")"
# A native compiler cannot resolve this shell's own path mapping: a search
# path built from the shell's `pwd` finds no prelude at all, and a scratch
# directory named `/tmp/tmp.X` is silently ignored on the search path, so
# the patched copy is never read and the proof that a check can fail
# quietly stops proving it.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT)
    REPO="$(cygpath -m "$REPO")"
    WORK="$(cygpath -m "$WORK")"
    ;;
esac

cd "$WORK" || exit 1
step() { echo "== $1"; }

cat > math_test.ri <<'RIS'
def check(name : String, ok : Bool) : Nil
  return if ok
  puts "FAIL: #{name}"
  __iyi_exit(1)
end

check("adds", 2 + 2 == 4)
check("concats", "a" + "b" == "ab")
RIS

step "passing tests exit 0, and --json is data"
"$RIS" test --json . > run.json 2>&1 || { cat run.json; exit 1; }
grep -Eq '"status": ?"pass"' run.json || { echo "no pass in the report:"; cat run.json; exit 1; }
grep -Eq '"failed": ?0' run.json || { echo "a passing run reported failures:"; cat run.json; exit 1; }

step "a failing test names itself and its evidence"
printf 'puts "the evidence line"\n__iyi_exit(1)\n' > broken_test.ri
"$RIS" test . > run.txt 2>&1
[ $? -eq 1 ] || { echo "a failing test did not fail the run:"; cat run.txt; exit 1; }
grep -q 'broken_test.ri: fail' run.txt || { echo "the failing file is unnamed:"; cat run.txt; exit 1; }
grep -q 'the evidence line' run.txt || { echo "the test's own output is missing:"; cat run.txt; exit 1; }
rm broken_test.ri

step "a test that does not build is a verdict, not a crash"
printf 'this is not iyi\n' > syntax_test.ri
"$RIS" test . > build.txt 2>&1
[ $? -eq 1 ] || { echo "an unbuildable test passed:"; cat build.txt; exit 1; }
grep -q 'syntax_test.ri: does not build' build.txt || { echo "the verdict is wrong:"; cat build.txt; exit 1; }
rm syntax_test.ri

step "a hanging test is killed at the deadline"
printf 'while true\nend\n' > hang_test.ri
timeout 30 "$RIS" test --timeout 2 . > hang.txt 2>&1
status=$?
[ $status -eq 1 ] || { echo "the hang was not a failure (exit $status, 124 is the harness hanging):"; cat hang.txt; exit 1; }
grep -q 'hang_test.ri: hung' hang.txt || { echo "the hang is unnamed:"; cat hang.txt; exit 1; }
rm hang_test.ri
# And a test whose time runs out while a program it started runs: the
# test's output comes through a pipe, and the child held it open, so only
# the test was killed and the run waited out the child - `ping -n 25`
# answered "hung" after 25 seconds. The deadline ends the whole tree.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT)
    printf 'module hang_child_test\n\nimport std/process::{Process}\n\nProcess.run("ping", ["-n", "25", "127.0.0.1"], capture: false)\n' > hang_child_test.ri
    started=$(date +%s)
    timeout 60 "$RIS" test --timeout 3 . > hang_child.txt 2>&1
    status=$?
    took=$(( $(date +%s) - started ))
    [ $status -eq 1 ] && grep -q 'hang_child_test.ri: hung' hang_child.txt ||
      { echo "a test hung on its child was not killed (exit $status):"; cat hang_child.txt; exit 1; }
    [ "$took" -lt 20 ] || { echo "a test hung on its child took ${took}s to be killed at 3"; exit 1; }
    rm hang_child_test.ri
    ;;
esac

step "the discount says when it turns itself off"
# `--affected` is an exactness claim — "only the tests whose imports reach
# the change" — and a changed file that is gone turns it off, because a
# deleted import breaks whoever held it and the closure cannot see that.
# It used to turn off in silence, so a mistyped path produced a full run
# that read as a selective one.
mkdir -p calc
printf 'module calc/add\n\npub def add(a : Int32, b : Int32) : Int32\n  a + b\nend\n' > calc/add.ri
printf 'module main\n\nimport calc/add::{add}\n\nraise "bad" if add(1, 2) != 3\n' > add_test.ri
printf 'module main\n\nputs "lonely"\n' > lonely_test.ri
"$RIS" test --affected calc/add.ri . > sel.txt 2>&1
grep -qE '1 passed, 0 failed, [0-9]+ skipped' sel.txt ||
  { echo "the selection is not exact:"; cat sel.txt; exit 1; }
# The same file under another spelling, where the file system says it is
# one: in upper case, and on Windows with the drive letter an editor
# writes lower case. The closure compared strings, and both selected
# nothing - "0 to run, 1 skipped", a clean verdict about no tests.
if [ CALC/ADD.IYI -ef calc/add.ri ]; then
  "$RIS" test --affected CALC/ADD.IYI . > sel_case.txt 2>&1
  grep -qE '1 passed, 0 failed, [0-9]+ skipped' sel_case.txt ||
    { echo "another case of the changed file selected otherwise:"; cat sel_case.txt; exit 1; }
fi
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT)
    lower="$(echo "$WORK" | cut -c1 | tr 'A-Z' 'a-z')$(echo "$WORK" | cut -c2-)/calc/add.ri"
    "$RIS" test --affected "$lower" . > sel_drive.txt 2>&1
    grep -qE '1 passed, 0 failed, [0-9]+ skipped' sel_drive.txt ||
      { echo "a lower-case drive letter selected otherwise:"; cat sel_drive.txt; exit 1; }
    # And the 8.3 short name, which a CI runner's temporary directory is
    # spelled in (`RUNNER~1`) while the working directory is the long one:
    # the lower-case drive above selected nothing there for that reason.
    short="$(cygpath -d "$WORK/calc/add.ri")"
    "$RIS" test --affected "$short" . > sel_short.txt 2>&1
    grep -qE '1 passed, 0 failed, [0-9]+ skipped' sel_short.txt ||
      { echo "the 8.3 short name selected otherwise ($short):"; cat sel_short.txt; exit 1; }
    # And spelled verbatim, `\\?\C:\...` or `\\.\C:\...`, the form Rust's
    # `fs::canonicalize` hands over: the prefix stayed in the key, no
    # closure held `\\?\c:\...`, and it was "0 to run, 1 skipped".
    for prefix in '\\?\' '\\.\'; do
      "$RIS" test --affected "$prefix$(cygpath -w "$WORK/calc/add.ri")" . > sel_verbatim.txt 2>&1
      grep -qE '1 passed, 0 failed, [0-9]+ skipped' sel_verbatim.txt ||
        { echo "the changed file spelled $prefix selected otherwise:"; cat sel_verbatim.txt; exit 1; }
    done
    ;;
esac
"$RIS" test --affected nope.ri . > off.txt 2>&1
grep -q 'nope.ri is not there, so every test ran' off.txt ||
  { echo "the discount turned off in silence:"; cat off.txt; exit 1; }
grep -qE '[0-9]+ passed, 0 failed$' off.txt ||
  { echo "the full run did not happen:"; cat off.txt; exit 1; }
"$RIS" test --json --affected nope.ri . > off.json 2>&1
grep -q '"affected_not_found":\["nope.ri"\]' off.json ||
  { echo "the data says nothing about it:"; cat off.json; exit 1; }
# A changed file no import can name is in no closure either: a template a
# test renders through `Eiy.render`, and the prelude every test compiles.
# Both were "0 to run, 1 skipped: no test's imports reach the change", and
# `check --affected` on a template that no longer parses said "0
# consumer(s) checked, all compile", exit 0.
printf 'hello <%%= 1 + 1 %%>\n' > page.eiy
printf 'import std/eiy::{Eiy}\n\nassert Eiy.render("page.eiy") == "hello 2\\n", "rendered"\n' > page_test.ri
"$RIS" test --affected page.eiy . > tmpl.txt 2>&1
grep -q 'page.eiy is not a module an import can name, so every test ran' tmpl.txt &&
  grep -qE '[0-9]+ passed, 0 failed$' tmpl.txt ||
  { echo "a changed template discounted the run:"; cat tmpl.txt; exit 1; }
"$RIS" test --json --affected "$REPO/src/ris/prelude.ri" . > prelude.json 2>&1
grep -q '"affected_not_imported":\[' prelude.json && grep -Eq '"skipped": ?0' prelude.json ||
  { echo "a changed prelude file discounted the run:"; cat prelude.json; exit 1; }
printf 'hello <%%= 1 + %%>\n)\n' > page.eiy
"$RIS" check types --affected page.eiy > tmpl_check.txt 2>&1
[ $? -eq 1 ] && grep -q '^page_test.ri: ' tmpl_check.txt ||
  { echo "a template that no longer parses broke no consumer:"; cat tmpl_check.txt; exit 1; }
rm page.eiy page_test.ri

step "a test named more than once runs once"
# The list was made unique as strings, so a test the directory walk found
# and the caller named again in two more spellings was built and run three
# times and counted as three passes.
"$RIS" test --json . add_test.ri "$WORK/add_test.ri" > once.json 2>&1
"$RIS" test --json . > all.json 2>&1
passed() { grep -oE '"passed": ?[0-9]+' "$1" | grep -oE '[0-9]+$'; }
[ -n "$(passed all.json)" ] && [ "$(passed once.json)" = "$(passed all.json)" ] ||
  { echo "a test named again was counted again: $(passed once.json) passes where the directory has $(passed all.json)"; cat once.json; exit 1; }

step "a flag is a flag, and a directory is not a changed file"
"$RIS" test --nonesuch . > flag.txt 2>&1
[ $? -eq 1 ] && grep -q 'unknown flag --nonesuch' flag.txt ||
  { echo "an unknown flag was read as a path:"; cat flag.txt; exit 1; }
"$RIS" test --affected . . > dir.txt 2>&1
[ $? -eq 1 ] && grep -q 'is a directory, not a changed file' dir.txt ||
  { echo "a directory was accepted as a changed file:"; cat dir.txt; exit 1; }

step "a timeout is a wait, so zero, less and more than a clock holds are refused"
# `--timeout 0` and `--timeout -1` were taken, and every test came back
# "hung: killed at -1.0s" - a verdict about the flag, printed as one about
# the tests, and a run an agent computing its budget could produce. And
# one past what the clock counts went wrong after the test was built:
# `1e300` overflowed the span the wait becomes, "Arithmetic overflow
# (OverflowError)" and "you've found a bug", and `9.3e14` hung a run of
# tests that end at once past a minute on Windows, though not every time
# (hence the `timeout`).
for wait in 0 -1 inf nan 1e300 9.3e14; do
  timeout 120 "$RIS" test --timeout "$wait" . > wait.txt 2>&1
  [ $? -eq 1 ] && grep -q -- "$wait is not a wait" wait.txt ||
    { echo "--timeout $wait was taken as a deadline:"; cat wait.txt; exit 1; }
done
grep -q 'hung' wait.txt && { echo "the refusal ran a test first:"; cat wait.txt; exit 1; }

step "a test that died says what killed it"
# An infinite recursion was "fail" with nothing under it - the one failure
# that printed no evidence, from the verb whose contract is that a failure
# prints its own. The program says `stack overflow` itself now, and a
# death the kernel still owns - a `Pointer` at nothing - is named by the
# verb as the evidence.
printf 'module deep_test\n\ndef down(n : Int32) : Int32\n  down(n + 1) + 1\nend\n\nputs down(0)\n' > deep_test.ri
"$RIS" test deep_test.ri > deep.txt 2>&1
[ $? -eq 1 ] || { echo "a test that died was not a failure:"; cat deep.txt; exit 1; }
grep -q 'deep_test.ri: fail' deep.txt || { echo "the dead test is unnamed:"; cat deep.txt; exit 1; }
grep -q 'stack overflow' deep.txt || { echo "the death is not the evidence:"; cat deep.txt; exit 1; }
"$RIS" test --json deep_test.ri > deep.json 2>&1
grep -q '"status":"fail"' deep.json && grep -q 'stack overflow' deep.json ||
  { echo "the data says nothing about the death:"; cat deep.json; exit 1; }
rm deep_test.ri
printf 'module wild_test\n\np = Pointer(Int32).new(16_u64)\nputs p.value\n' > wild_test.ri
"$RIS" test wild_test.ri > wild.txt 2>&1
[ $? -eq 1 ] || { echo "a test the kernel killed was not a failure:"; cat wild.txt; exit 1; }
grep -q 'memory fault' wild.txt || { echo "the kernel's kill is not the evidence:"; cat wild.txt; exit 1; }
rm wild_test.ri

step "an assertion's failure is its evidence, and named cases keep going"
# `assert(a == b)` failed with "assertion failed" alone. The prelude's
# assertions name the values and the line, and that is what the verb
# shows under the file it names (`test/cli/assertions_exercise.sh` drives
# each assertion; this is the verb's side of the contract).
printf 'module eq_test\n\nsum = 2 + 3\nassert_eq 4, sum, "the sum"\n' > eq_test.ri
"$RIS" test eq_test.ri > eq.txt 2>&1
[ $? -eq 1 ] || { echo "a failed assert_eq did not fail the run:"; cat eq.txt; exit 1; }
grep -q 'eq_test.ri: fail' eq.txt && grep -q 'assert_eq failed: the sum' eq.txt &&
  grep -q 'expected: 4' eq.txt && grep -q 'actual: 5' eq.txt && grep -qE 'at .*eq_test.ri:4$' eq.txt ||
  { echo "the failure does not name its values and its line:"; cat eq.txt; exit 1; }
rm eq_test.ri
# iyi's named `test "x" do` cases are gone (spec blocks, D9): refused.
printf 'module cases_test\n\ntest "first" { assert_eq 1, 1 }\n' > cases_test.ri
"$RIS" test cases_test.ri > cases.txt 2>&1 &&
  { echo "a named test case was accepted:"; cat cases.txt; exit 1; }
grep -q 'write `spec N.M`' cases.txt ||
  { echo "the refusal does not name spec N.M:"; cat cases.txt; exit 1; }
rm cases_test.ri

step "a test leaves nothing in the temporary directory"
# Each test is built to a temporary name and deleted after it runs. On
# Windows the name had no extension, the build appended `.exe`, and the
# delete asked for the name without it: every test left its program and
# its `.pdb` behind, and a developer's %TEMP% held hundreds of them.
mkdir -p scratch_tmp
scratch="$WORK/scratch_tmp"
TMPDIR="$scratch" TMP="$scratch" TEMP="$scratch" "$RIS" test math_test.ri > tmp.txt 2>&1 ||
  { echo "the test did not pass:"; cat tmp.txt; exit 1; }
left="$(ls -A "$scratch")"
[ -z "$left" ] || { echo "a test left behind:"; echo "$left"; exit 1; }

step "-j 4 gives the verdicts and order of -j 1"
mkdir -p par && (
  cd par || exit 1
  printf '__iyi_exit(0)\n' > a_pass_test.ri
  printf 'puts "b failed"\n__iyi_exit(1)\n' > b_fail_test.ri
  printf 'this does not build (\n' > c_nobuild_test.ri
  printf 'while true\n  sleep 100\nend\n' > d_hang_test.ri
  printf '__iyi_exit(0)\n' > e_pass_test.ri
)
"$RIS" test --timeout 3 -j 1 par > j1.txt 2>&1; j1=$?
"$RIS" test --timeout 3 -j 4 par > j4.txt 2>&1; j4=$?
[ "$j1" -eq 1 ] && [ "$j4" -eq 1 ] ||
  { echo "exit codes -j1=$j1 -j4=$j4"; cat j1.txt j4.txt; exit 1; }
diff <(grep -v 'passed,' j1.txt) <(grep -v 'passed,' j4.txt) ||
  { echo "-j 4 differs from -j 1"; exit 1; }
grep -q '2 passed, 3 failed' j4.txt ||
  { echo "wrong tally:"; cat j4.txt; exit 1; }
order="$(grep -o '[a-e]_[a-z]*_test.ri: [a-z ]*' j4.txt | cut -c1 | tr -d '\n')"
[ "$order" = "bcd" ] || { echo "order $order, want bcd:"; cat j4.txt; exit 1; }
"$RIS" test --timeout 3 -j 4 --json par > j4.json 2>&1
python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
s=[t["status"].split(":")[0] for t in d["tests"]]
assert s==["pass","fail","does not build","hung","pass"], s
' j4.json || { cat j4.json; exit 1; }

step "RIS_JOBS sets the default, and a bad value is refused"
RIS_JOBS=2 "$RIS" test --timeout 3 par > env.txt 2>&1
diff <(grep -v 'passed,' j1.txt) <(grep -v 'passed,' env.txt) ||
  { echo "RIS_JOBS=2 differs"; exit 1; }
RIS_JOBS=zero "$RIS" test par > envbad.txt 2>&1
grep -q 'RIS_JOBS takes a number' envbad.txt ||
  { echo "RIS_JOBS=zero not refused:"; cat envbad.txt; exit 1; }

step "8 small tests: -j 1 vs -j 8 (timed, never fails)"
mkdir -p eight
for i in 1 2 3 4 5 6 7 8; do
  printf '__iyi_exit(0)\n' > "eight/t${i}_test.ri"
done
t0=$(date +%s.%N)
"$RIS" test -j 1 eight > e1.txt 2>&1 || { cat e1.txt; exit 1; }
t1=$(date +%s.%N)
"$RIS" test -j 8 eight > e8.txt 2>&1 || { cat e8.txt; exit 1; }
t2=$(date +%s.%N)
awk -v a="$t0" -v b="$t1" -v c="$t2" \
  'BEGIN { printf "timing: 8 tests -j 1 %.2fs, -j 8 %.2fs\n", b-a, c-b }'

echo "workdir $WORK"
echo "test verb gate: every step held"
exit 0
