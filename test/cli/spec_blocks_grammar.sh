#!/usr/bin/env bash
# Spec blocks: grammar, place and strip (doc/drafts/spec-blocks/
# spec-blocks.md 5.1, 5.4, 5.6 strip only; step 2).
#
#     bash test/cli/spec_blocks_grammar.sh
#
# A module with code, then spec blocks (one after a test-only
# `import std/dir`) and a private helper, builds and runs; its binary
# holds no string and no std/dir symbol of the section. Each refused
# shape gives its message, the formatter leaves the file unchanged and
# `ris doc` shows nothing of the section.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
IYI="${IYI:-$REPO/bin/ris}"
case "$IYI" in /*) ;; *) IYI="$PWD/$IYI" ;; esac
mkdir -p "$REPO/test/cli/.work"
WORK="$(mktemp -d "$REPO/test/cli/.work/XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

failed=0
fail() { echo "FAIL: $*"; failed=1; }

cat > m.ri <<'EOF'
module m

pub def greet : String
  "hello from m"
end

puts greet

spec 1.1  # Running m.ri prints `hello from m`.
  greet == "hello from m"
  "BLOCKMARKER_ONLY_IN_SPEC".size > 0
end

import std/dir::{Dir}

spec 1.2
  Dir.exists?(".")
  helper_marker.size > 0
end

spec 1.2
  todo "a second block for the same clause"
end

private def helper_marker : String
  "HELPERMARKER_ONLY_IN_SECTION"
end
EOF

echo "== build and run"
"$IYI" build m.ri -o m > build.out 2>&1 || { fail "build:"; cat build.out; }
if [ -x m ]; then
  out="$(./m)"
  [ "$out" = "hello from m" ] || fail "run printed: $out"
  if grep -q -a -e BLOCKMARKER -e HELPERMARKER m; then
    fail "the binary holds a string of the spec section"
  fi
  if nm m 2>/dev/null | grep -q 'Std::Dir'; then
    fail "the binary holds a std/dir symbol"
  fi
fi

# The control: std/dir imported above the section does leave symbols,
# so the check above can see them.
sed -e 's/^module m$/module m\n\nimport std\/dir::{Dir}/' \
  -e 's/^puts greet$/puts Dir.exists?(".")/' \
  -e '/^spec 1.1/,$d' m.ri > control.ri
"$IYI" build control.ri -o control > control.out 2>&1 ||
  { fail "control build:"; cat control.out; }
if [ -x control ] && ! nm control 2>/dev/null | grep -q 'Std::Dir'; then
  fail "control: no Std::Dir symbol found, the symbol check sees nothing"
fi

echo "== format leaves the file unchanged"
cp m.ri before.ri
"$IYI" check format m.ri > fmt.out 2>&1 ||
  { fail "check format:"; cat fmt.out; }
"$IYI" check format --fix m.ri > fmt.out 2>&1 ||
  { fail "check format --fix:"; cat fmt.out; }
cmp -s before.ri m.ri || { fail "format changed m.ri:"; diff before.ri m.ri; }
# The formatter does run: it fixes the def, and keeps the block as written.
printf 'module f\n\npub def two : Int32\n  a  =  2\n  a\nend\n\nspec 1.1   #  odd  label\n    two  ==  2\nend\n' \
  > f.ri
sed -n '/^spec/,$p' f.ri > f.block
"$IYI" check format --fix f.ri > fmt.out 2>&1 ||
  { fail "check format --fix f.ri:"; cat fmt.out; }
grep -qx '  a = 2' f.ri || { fail "format did not fix f.ri:"; cat f.ri; }
sed -n '/^spec/,$p' f.ri | cmp -s - f.block ||
  { fail "format changed the block:"; cat f.ri; }

echo "== export metadata omits the section"
printf 'import m\n\nputs M.greet\n' > main.ri
"$IYI" build main.ri --no-codegen --emit-iyimod meta > meta.out 2>&1 ||
  { fail "emit-iyimod:"; cat meta.out; }
ls meta/* > /dev/null 2>&1 || fail "no .iyimod written"
if grep -r -q -e 'std/dir' -e helper_marker meta; then
  fail "the export metadata names the spec section"
fi

echo "== doc omits the section"
"$IYI" doc m.ri > doc.out 2>&1 || { fail "doc:"; cat doc.out; }
grep -q greet doc.out || { fail "doc lacks greet:"; cat doc.out; }
if grep -q -e helper_marker -e 'spec 1' -e 'Dir' doc.out; then
  fail "doc shows the spec section:"; cat doc.out
fi

# refuse NAME EXPECTED: build NAME.ri, which must fail with EXPECTED.
refuse() {
  "$IYI" build "$1.ri" -o "$1" > "$1.out" 2>&1 &&
    { fail "$1 built"; return; }
  grep -qF -- "$2" "$1.out" || { fail "$1: wanted \"$2\", got:"; cat "$1.out"; }
}

echo "== refused shapes"
head='module r

pub def one : Int32
  1
end
'
printf '%s\nspec "one is one"\n  one == 1\nend\n' "$head" > text.ri
refuse text 'a spec block names a SPEC.md clause: `spec 1.2`'
printf '%s\nspec 1.2 do\n  one == 1\nend\n' "$head" > do.ri
refuse do 'a spec block takes no `do`'
printf '%s\nspec\n  one == 1\nend\n' "$head" > bare.ri
refuse bare '`spec` starts a spec block and needs a SPEC.md clause'
printf '%s\nspec = 3\n' "$head" > assign.ri
refuse assign '`spec` at the start of a top-level line starts a spec block'
printf 'module r\n\ndef spec : Int32\n  1\nend\n' > defspec.ri
refuse defspec '`spec` starts a spec block; name the def otherwise'
printf '%s\ntest "x" do\nend\n\nspec 1.2\n  one == 1\nend\n' "$head" \
  > oldtest.ri
refuse oldtest 'a check names a SPEC clause: write `spec N.M`'

echo "== the spec section"
printf '%s\nspec 1.2\n  one == 1\nend\n\ndef render : Int32\n  2\nend\n' \
  "$head" > after.ri
refuse after '`def render` comes after the spec block at after.ri:7; move it above the first `spec`'
printf '%s\nspec 1.2\n  one == 1\nend\n\nputs 1\n' "$head" > call.ri
refuse call 'comes after the spec block at call.ri:7'
printf '%s\nspec 1.2\n  one == 1\nend\n\nprivate def one : Int32\n  2\nend\n' \
  "$head" > shadow.ri
refuse shadow 'the helper `one` would replace the code under proof'

[ "$failed" = 0 ] && echo "ok: spec blocks parse, are refused and stripped"
exit "$failed"
