#!/usr/bin/env bash
# `ris init` writes a project whose clause 1.1 is proven by a spec block
# at the end of its root module, reviewed in .spec.lock, with no test/
# (doc/drafts/spec-blocks/spec-blocks.md 5.11, step 7).
#
#     bash test/cli/spec_blocks_init.sh
#
# It wrote test/NAME_test.ri: a `# spec: 1.1@HASH` tag and a todo, with
# no `module` header, and an AGENTS.md teaching tags.
#
# spec: 6.9@1e0b6a98

set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
IYI="${IYI:-$REPO/bin/ris}"
mkdir -p "$REPO/test/cli/.work"
WORK="$(mktemp -d "$REPO/test/cli/.work/XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export IYI_PATH="$REPO/src"
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
"$IYI" init demo app > init.txt 2>&1
say "init writes the project" $?
say "no test/ is written" "$([ ! -e app/test ]; echo $?)"
grep -qxF '  demo == "hello from demo\n"' app/demo.ri &&
  grep -qx 'spec 1\.1  # Running demo.ri prints `hello from demo`\.' \
    app/demo.ri
say "demo.ri ends with a spec block checking the output (4.5)" $?
say ".spec.lock reviews 1.1" \
  "$(grep -qx '1\.1 [0-9a-f]\{8\}' app/.spec.lock; echo $?)"
grep -qF 'spec N.M' app/AGENTS.md && ! grep -q '# spec:' app/AGENTS.md
say "AGENTS.md teaches spec blocks, not tags" $?
"$IYI" init --help > help.txt 2>&1
say "the usage names .spec.lock, not a test file" \
  "$(grep -q .spec.lock help.txt && ! grep -q _test.ri help.txt; echo $?)"

(cd app && "$IYI" check) > check.txt 2>&1
say "ris check is green: $(tail -1 check.txt)" $?
(cd app && "$IYI" spec) > spec.txt 2>&1
say "ris spec shows 1.1 ok" "$(grep -q '^1\.1 *ok ' spec.txt; echo $?)"
say "ris check ran the block" \
  "$(grep -q '^test *ok' check.txt; echo $?)"
# A block that fails makes ris check fail: the block is run, not listed.
sed -i 's/hello from demo\\n/nope\\n/' app/demo.ri
(cd app && "$IYI" check) > broken.txt 2>&1
say "a broken block fails ris check" \
  "$([ $? -ne 0 ] && grep -q '^test *FAIL\|^test *fail' broken.txt; echo $?)"
(cd app && "$IYI" spec todo) > todo.txt 2>&1
say "nothing is left todo: $(tail -1 todo.txt)" \
  "$(! grep -q '1\.1' todo.txt; echo $?)"

# A SPEC.md already there is the project's own: no clause 1.1 of init's,
# so no block proving it.
mkdir own && printf '# own\n' > own/SPEC.md
"$IYI" init own own > own.txt 2>&1
say "with its own SPEC.md, no spec block and no .spec.lock" \
  "$(! grep -q '^spec ' own/own.ri && [ ! -e own/.spec.lock ]; echo $?)"

exit $status
