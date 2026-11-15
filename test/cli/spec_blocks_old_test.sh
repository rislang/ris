#!/usr/bin/env bash
# iyi's `test "x" do` is gone: a check is a spec block (D9, step 8 of
# doc/drafts/spec-blocks/spec-blocks.md).
#
#     bash test/cli/spec_blocks_old_test.sh
#
# Before, a program could still hold named `test "x"` cases away from a
# spec section; the prelude ran them and printed `ok - x`.

set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RIS="${RIS:-$REPO/bin/ris}"
case "$RIS" in /*) ;; *) RIS="$PWD/$RIS" ;; esac
mkdir -p "$REPO/test/cli/.work"
WORK="$(mktemp -d "$REPO/test/cli/.work/XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export RIS_PATH="$REPO/src"
status=0

say() {
  if [ "$2" -eq 0 ]; then
    echo "  ok   $1"
  else
    echo "  FAIL $1"
    status=1
  fi
}

cd "$WORK" || exit 1
fix='write `spec N.M`; add the clause to SPEC.md first if none fits'

printf 'module cases_test\n\ntest "one" do\n  assert_eq 1, 1\nend\n' \
  > cases_test.ri
"$RIS" test cases_test.ri > test.txt 2>&1
say "ris test refuses a named case in a *_test.ri" \
  "$([ $? -ne 0 ] && grep -qF "$fix" test.txt; echo $?)"
printf 'module main\n\ntest "one" { assert_eq 1, 1 }\n' > plain.ri
"$RIS" build plain.ri > build.txt 2>&1
say "ris build refuses one in a program, naming the fix" \
  "$([ $? -ne 0 ] && grep -qF "$fix" build.txt; echo $?)"

# A method or variable named test is no check and stays allowed.
printf '%s\n' 'module main' '' 'class F' '  def test(s : String) : String' \
  '    s' '  end' 'end' '' 'test = F.new' 'puts test.test("fine")' > method.ri
"$RIS" run method.ri > method.txt 2>&1
say "a method named test still works" \
  "$(grep -qx fine method.txt; echo $?)"

grep -qE 'def test\(name|IyiTestCases' "$REPO/src/ris/testing.ri" \
  "$REPO/src/ris/prelude.ri"
say "the prelude no longer defines test or IyiTestCases" \
  "$([ $? -ne 0 ]; echo $?)"

# Gate of step 8: a project needs no test/.
"$RIS" init demo app > init.txt 2>&1
(cd app && "$RIS" check) > check.txt 2>&1
say "ris check is green in a fresh project with no test/" \
  "$([ $? -eq 0 ] && [ ! -e app/test ]; echo $?)"

exit "$status"
