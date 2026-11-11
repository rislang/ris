#!/usr/bin/env bash
# Spec blocks: test-only imports (doc/drafts/spec-blocks/spec-blocks.md
# 5.6; step 5).
#
#     bash test/cli/spec_blocks_imports.sh
#
# An import in the spec section is for the blocks only: a block that
# imports std/dir there builds and runs under `ris test`; the plain build,
# the module's .iyimod and `ris doc` name nothing from it. A test-only
# import of a module that imports this one is refused. `ris test
# --affected F` counts a spec-section import as the module's dependency.
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
has() { grep -qF -- "$2" "$1" || { fail "$1 lacks: $2"; cat "$1"; }; }

cat > SPEC.md <<'EOF'
# Demo

## 1. Model

* 1.1 The answer is 42.
EOF

mkdir -p proj/cyc
cat > proj/helper.ri <<'EOF'
module proj/helper

pub def forty : Int32
  40
end
EOF

cat > proj/m.ri <<'EOF'
module proj/m

pub def answer : Int32
  42
end

spec 1.1
  answer == 42
end

import std/dir::{Dir}
import proj/helper::{forty}

spec 1.1
  Dir.current.size > 0
  forty + 2 == answer
end
EOF

cat > main.ri <<'EOF'
import proj/m::{answer}

puts answer
EOF

echo "== ris test runs a block whose import is test-only"
"$IYI" test proj/m.ri > t.out 2>&1
rc=$?
[ "$rc" = 0 ] || { fail "ris test proj/m.ri exit $rc, want 0"; cat t.out; }
has t.out "2 blocks: 2 ok"

echo "== the plain build names nothing from std/dir"
"$IYI" build proj/m.ri -o plain > b.out 2>&1 \
  || { fail "build proj/m.ri:"; cat b.out; }
"$IYI" build --spec proj/m.ri -o specbin > s.out 2>&1 \
  || { fail "build --spec proj/m.ri:"; cat s.out; }
# The probe sees Dir where it is: else the check below proves nothing.
nm specbin 2>/dev/null | grep -q 'Dir' \
  || fail "the test program has no Dir symbol: nm cannot tell"
if [ -f plain ] && nm plain 2>/dev/null | grep -q 'Dir'; then
  fail "the plain binary has a Dir symbol:"
  nm plain | grep 'Dir' | head -5
fi

echo "== .iyimod and ris doc name nothing from the section"
"$IYI" build --emit-iyimod mods -o main main.ri > e.out 2>&1 \
  || { fail "build --emit-iyimod:"; cat e.out; }
if grep -rlE 'std/dir|helper' mods > /dev/null 2>&1; then
  fail "an .iyimod names a test-only import:"
  grep -rlE 'std/dir|helper' mods
fi
"$IYI" doc proj/m.ri > d.out 2>&1 || { fail "ris doc:"; cat d.out; }
if grep -qE 'std/dir|Dir|forty' d.out; then
  fail "ris doc names a test-only import:"; cat d.out
fi

echo "== ris test --affected counts a spec-section import"
"$IYI" test --affected proj/helper.ri proj/m.ri > a.out 2>&1
rc=$?
[ "$rc" = 0 ] || { fail "--affected helper exit $rc"; cat a.out; }
has a.out "2 blocks: 2 ok"
# An unrelated module skips it: else the line above proves nothing.
printf 'module proj/u\n\npub def u : Int32\n  1\nend\n' > proj/u.ri
"$IYI" test --affected proj/u.ri proj/m.ri > u.out 2>&1
has u.out "no test's imports reach the change"

echo "== a test-only import of a module importing this one is refused"
cat > proj/cyc/post.ri <<'EOF'
module proj/cyc/post

pub def title : String
  "t"
end

spec 1.1
  title == "t"
end

import proj/cyc/site::{page}

spec 1.1
  page == "<h1>t</h1>"
end
EOF
cat > proj/cyc/site.ri <<'EOF'
module proj/cyc/site

import proj/cyc/post::{title}

pub def page : String
  "<h1>" + title + "</h1>"
end
EOF
"$IYI" test proj/cyc/post.ri > c.out 2>&1
rc=$?
[ "$rc" != 0 ] || fail "a cyclic test-only import passed"
has c.out "the proof of post imports site, which imports post; prove it in site.ri"

[ "$failed" = 0 ] && echo "spec_blocks_imports: ok"
exit "$failed"
