#!/usr/bin/env bash
# Spec blocks: the module test program (doc/drafts/spec-blocks/
# spec-blocks.md 5.2, 5.3, 5.5, 5.8; step 3).
#
#     bash test/cli/spec_blocks_run.sh
#
# A tiny project with SPEC.md. `ris test` builds each module with
# `build --spec` and runs its blocks: a block on a private def passes; a
# failed line prints clause, file:line, its text and both sides, and the
# next line still runs; a failed `=~` prints pattern and text; a panic
# ends only its block; exit 1. todo alone gives 77. An unknown clause, a
# block that checks nothing and a `Bool?` line are refused.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RIS="${RIS:-$REPO/bin/ris}"
case "$RIS" in /*) ;; *) RIS="$PWD/$RIS" ;; esac
mkdir -p "$REPO/test/cli/.work"
WORK="$(mktemp -d "$REPO/test/cli/.work/XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

# A pure library proof must not import process helpers back into itself.
# ris_spec -> dir -> path used to make std/path's own proofs cyclic.
(cd "$REPO" && "$RIS" test src/std/path.ri) > path.out 2>&1
if [ $? -ne 0 ]; then
  echo 'FAIL: pure std/path spec has an import cycle'
  tail -15 path.out
  exit 1
fi

failed=0
fail() { echo "FAIL: $*"; failed=1; }
has() { grep -qF -- "$2" "$1" || { fail "$1 lacks: $2"; cat "$1"; }; }

cat > SPEC.md <<'EOF'
# Demo

## 1. Model

* 1.1 The answer is 42.
* 1.2 Names are greeted.
* 1.3 A page names its title.
* 1.4 Nothing panics.
* 1.5 Later work.
EOF

# Libraries keep computed constants and can derive their own types.
cat > constants.ri <<'EOF'
module constants

VALUES = Array(Int32).new(2) { |i| i + 20 }

pub def answer : Int32
  VALUES[0] + VALUES[1] + 1
end

spec 1.1
  answer == 42
end
EOF
"$RIS" test constants.ri > constants.out 2>&1
[ $? = 0 ] || { fail "computed library constant"; tail -15 constants.out; }
rm constants.ri

cat > derived.ri <<'EOF'
module derived

pub trait Answer
  abstract def answer : Int32
end

pub macro own(declaration)
  impl ::Derived::Answer for {{ declaration[:name].id }}
    def answer : Int32
      42
    end
  end
end

pub struct Value
  derive own
end

spec 1.1
  Value.new.answer == 42
end
EOF
"$RIS" test derived.ri > derived.out 2>&1
[ $? = 0 ] || { fail "module's own derive"; tail -15 derived.out; }
rm derived.ri

# A nested platform branch inside a declaration is still a declaration.
cat > conditional.ri <<'EOF'
module conditional
{% if true %}
  pub struct Value
    {% if true %}
      def answer : Int32
        42
      end
    {% else %}
      def answer : Int32
        41
      end
    {% end %}
  end
{% end %}
spec 1.1
  Value.new.answer == 42
end
EOF
"$RIS" test conditional.ri > conditional.out 2>&1
[ $? = 0 ] || { fail "nested conditional declaration"; tail -15 conditional.out; }
rm conditional.ri

mkdir proj
cat > proj/m.ri <<'EOF'
module m

pub def greet(name : String) : String
  "hello " + name
end

private def answer : Int32
  41 + 1
end

spec 1.1
  answer == 42
  answer > 40
end

spec 1.2
  greet("ann") == "hello bob"
  greet("ann").size == 99
  greet("ann").starts_with?("hello")
end

import std/regex::{Regex}

spec 1.3
  page = "<h1>Home</h1>"
  page =~ %r{<h1>About}
end

spec 1.4
  answer == 42
  boom
  answer == 0
end

spec 1.1
  answer == 42
end

private def boom : Nil
  raise "the block panics here"
end
EOF

cat > proj/t.ri <<'EOF'
module t

private def two : Int32
  2
end

spec 1.1
  two + 40 == 42
end

spec 1.5
  two == 2
  todo "not written yet"
end
EOF

echo "== a failing module: ris test proj/m.ri"
"$RIS" test proj/m.ri > m.out 2>&1
rc=$?
[ "$rc" = 1 ] || fail "m.ri exit $rc, want 1"
has m.out "ok  spec 1.1  proj/m.ri:11"
has m.out "BROKEN  spec 1.2  proj/m.ri:16"
has m.out 'proj/m.ri:17  greet("ann") == "hello bob"'
has m.out 'left:  "hello ann"'
has m.out 'right: "hello bob"'
has m.out 'proj/m.ri:18  greet("ann").size == 99'
has m.out "left:  9"
grep -q "proj/m.ri:19" m.out && fail "a passing line was reported"
has m.out "BROKEN  spec 1.3  proj/m.ri:24"
has m.out 'proj/m.ri:26  page =~ %r{<h1>About}'
has m.out "pattern: /<h1>About/"
has m.out 'text:    "<h1>Home</h1>"'
has m.out "BROKEN  spec 1.4  proj/m.ri:29"
has m.out "panic: the block panics here"
grep -q "proj/m.ri:32" m.out && fail "a line after the panic ran"
has m.out "ok  spec 1.1  proj/m.ri:35"
has m.out "1 module, 5 blocks: 2 ok, 3 broken, 0 todo"

echo "== the test program alone: build --spec, RIS_SPEC_JSON"
"$RIS" build --spec proj/m.ri -o mbin > b.out 2>&1 \
  || { fail "build --spec:"; cat b.out; }
if [ -x mbin ]; then
  RIS_SPEC_JSON=1 ./mbin > j.out 2>/dev/null
  rc=$?
  [ "$rc" = 1 ] || fail "test program exit $rc, want 1"
  has j.out '{"clause":"1.2","ordinal":0,"file":"proj/m.ri","line":16,"status":"broken","failures":['
  has j.out '{"clause":"1.1","ordinal":1,'
fi

echo "== todo and nothing broken: 77"
"$RIS" test proj/t.ri > t.out 2>&1
rc=$?
[ "$rc" = 0 ] || fail "ris test t.ri exit $rc, want 0 (todo is no failure)"
has t.out "todo  spec 1.5  proj/t.ri:11  not written yet"
has t.out "1 module, 2 blocks: 1 ok, 0 broken, 1 todo"
"$RIS" build --spec proj/t.ri -o tbin > tb.out 2>&1 \
  || { fail "build --spec t.ri:"; cat tb.out; }
if [ -x tbin ]; then
  ./tbin > tr.out 2>&1
  rc=$?
  [ "$rc" = 77 ] || fail "t.ri test program exit $rc, want 77"
fi

echo "== ris test with no path walks every module"
"$RIS" test > all.out 2>&1
has all.out "2 modules, 7 blocks: 3 ok, 3 broken, 1 todo"

echo "== --json carries the blocks"
"$RIS" test --json proj/t.ri > tj.out 2>&1
has tj.out '"blocks":[{"clause":"1.1"'

refused() { # file, expected text
  mkdir -p bad
  printf '%s\n' "$2" > "bad/$1"
  "$RIS" test "bad/$1" > r.out 2>&1
  rc=$?
  [ "$rc" = 1 ] || fail "$1: exit $rc, want 1"
  has r.out "$3"
  rm -rf bad
}

echo "== refusals"
refused u.ri "module u

spec 9.9
  1 == 1
end" "no clause 9.9 in SPEC.md; add it there first, or name the clause this proves"

refused n.ri "module n

spec 1.1
  x = 1
end" "spec 1.1 at bad/n.ri:3 checks nothing; add a line that is a Bool"

refused n2.ri "module n2

private def one : Int32
  1
end

spec 1.1
  one
end" "spec 1.1 at bad/n2.ri:7 checks nothing; add a line that is a Bool"

refused q.ri "module q

private def maybe(flag : Bool) : Bool?
  flag ? true : nil
end

spec 1.1
  maybe(true)
end" "line 8 may be nil; write \`x == true\`"

refused a.ri "module a

spec 1.5
  todo \"first\"
  1 == 1
end" "nothing runs after \`todo\`; move it to the end of the block"

refused o.ri "module o

private def later : Nil
  todo \"no\"
end

spec 1.1
  1 == 1
end" "\`todo\` marks an unproved clause; put it in a \`spec N.M\` block"

[ "$failed" = 0 ] && echo "PASS: spec blocks run"
exit "$failed"
