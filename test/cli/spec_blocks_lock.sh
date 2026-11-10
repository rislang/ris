#!/usr/bin/env bash
# spec: 6.7@0845721d, 6.8@9832e912
# Spec blocks: `ris spec` on blocks, spec.lock, the clause label and the
# hint for a missing package spec import (doc/drafts/spec-blocks/
# spec-blocks.md 5.9, 5.10, 5.14-5.16; step 6).
#
#     bash test/cli/spec_blocks_lock.sh
#
# A block in src/ covers its clause; spec.lock holds the reviewed hash, so
# editing the clause fails `ris check spec` until `ris spec ack` (a stale
# old tag `@V` no longer counts); an orphan lock line fails; `ris check
# --fix` writes and refreshes labels, cut at a word with `…` within 80
# columns; a stale label fails; a fresh label does not clear "to review";
# `ris spec ack --from-tags` seeds the lock, and ris's own `ris check
# spec` is green; a block calling a name web/spec defines, in a file
# reaching web through site, is told the import to add.
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
version() { "$IYI" spec "$1" | head -1 | cut -d' ' -f1; }
changelog() {
  printf '## 2026-01-0%s · %s %s\n\nWhy.\n\n' "$1" "$(version 1.1)" \
    "$(version 1.2)" >> SPEC_CHANGELOG.md
}

cat > SPEC.md <<'EOF'
# Demo

## 1. Posts

* 1.1 A post needs a title.
* 1.2 A post's slug is its title in lower case, with every run of spaces
  and punctuation turned into one dash and no dash at either end of it.
EOF
echo "# Changelog" > SPEC_CHANGELOG.md
changelog 1

mkdir -p src test
cat > src/post.ri <<'EOF'
module src/post

pub def title_ok?(title : String) : Bool
  title.size > 0
end

spec 1.1
  title_ok?("a")
end

spec 1.2
  todo "slug comes later"
end
EOF
# An old file tag with a stale `@V` on 1.1.
printf '# spec: 1.1@00000000\nputs 1\n' > test/old_test.ri

# (a) the block in src/ covers its clause: not reviewed yet, so check fails.
"$IYI" spec > a.out 2>&1
has a.out "1.1   to review     2"
"$IYI" check spec > a2.out 2>&1
[ $? = 0 ] && fail "(a) unreviewed blocks passed check spec"
has a2.out "1.1 has proofs not reviewed yet"
has a2.out "review src/post.ri:7"

# (b) ack writes spec.lock and clears it despite the stale tag.
"$IYI" spec ack 1 > b.out 2>&1 || { fail "(b) ack"; cat b.out; }
grep -qx "1.1 $(version 1.1 | cut -d@ -f2)" spec.lock || fail "(b) no 1.1 line"
"$IYI" check spec > b2.out 2>&1 || { fail "(b) check after ack"; cat b2.out; }
has b2.out "1 ok, 1 todo, 0 to review"

# (c) editing the clause fails until ack.
sed -i 's/needs a title\./needs a title of one letter or more./' SPEC.md
changelog 2
"$IYI" check spec > c.out 2>&1
[ $? = 0 ] && fail "(c) an edited clause passed"
has c.out "1.1 changed since its proofs were reviewed"
"$IYI" spec ack 1.1 > /dev/null 2>&1
"$IYI" check spec > c2.out 2>&1 || { fail "(c) check after re-ack"; cat c2.out; }

# (d) an orphan lock line fails; any ack drops it.
echo "9.9 abcdef12" >> spec.lock
"$IYI" check spec > d.out 2>&1
[ $? = 0 ] && fail "(d) an orphan lock line passed"
has d.out "spec.lock holds 9.9, which is no clause of the spec"
"$IYI" spec ack 1.1 > /dev/null 2>&1
grep -q "^9.9" spec.lock && fail "(d) ack kept the orphan"

# (e) labels: --fix writes them; the long one is cut within 80 columns.
"$IYI" check spec --fix > e.out 2>&1 || { fail "(e) check --fix"; cat e.out; }
grep -qx "spec 1.1  # A post needs a title of one letter or more." src/post.ri ||
  fail "(e) 1.1 label not written"
long="$(grep '^spec 1.2' src/post.ri)"
case "$long" in
  "spec 1.2  # A post's slug is its title in lower case,"*"…") ;;
  *) fail "(e) 1.2 label not cut with …: $long" ;;
esac
[ "$(printf '%s' "$long" | wc -m)" -le 80 ] || fail "(e) label over 80 columns"
"$IYI" check spec > e2.out 2>&1 || { fail "(e) check after --fix"; cat e2.out; }
sed -i 's/^spec 1.1  # .*/spec 1.1  # A post needs nothing./' src/post.ri
"$IYI" check spec > e3.out 2>&1
[ $? = 0 ] && fail "(e) a stale label passed"
has e3.out "the label of spec 1.1 at src/post.ri:7 differs from SPEC.md"
has e3.out "run \`ris check --fix\`"
# A clause edit: --fix refreshes the label, but the clause stays to review.
sed -i 's/one letter or more\./a letter or more./' SPEC.md
changelog 3
"$IYI" check spec --fix > e4.out 2>&1
[ $? = 0 ] && fail "(e) a fresh label cleared to review"
grep -qx "spec 1.1  # A post needs a title of a letter or more." src/post.ri ||
  fail "(e) 1.1 label not refreshed"
has e4.out "1.1 changed since its proofs were reviewed"

# (f) --from-tags seeds the lock from matching tags.
mkdir f && cd f
printf '# Demo\n\n## 1. A\n\n* 1.1 One.\n' > SPEC.md
printf '# spec: 1.1@%s\nputs 1\n' "$("$IYI" spec 1.1 | head -1 | cut -d@ -f2 | cut -d' ' -f1)" > x_test.ri
mkdir test && mv x_test.ri test/
"$IYI" spec ack --from-tags > f.out 2>&1 || { fail "(f) --from-tags"; cat f.out; }
grep -q "^1.1 " spec.lock || fail "(f) --from-tags wrote no 1.1 line"
cd ..
(cd "$REPO" && "$IYI" check spec > "$WORK/f2.out" 2>&1) ||
  { fail "(f) ris's own check spec"; tail -5 f2.out; }
[ -f "$REPO/spec.lock" ] || fail "(f) ris has no spec.lock"

# (g) the hint for a missing package spec import, through site.
mkdir g && cd g
printf '# Demo\n\n## 1. A\n\n* 1.1 One.\n' > SPEC.md
mkdir web
printf 'module web/spec\n\npub def get(path : String) : Int32\n  200\nend\n' > web/spec.ri
printf 'module web/server\n\npub def serve : Int32\n  1\nend\n' > web/server.ri
printf 'module site\n\nimport web/server::{serve}\n\npub def run : Int32\n  serve\nend\n' > site.ri
cat > blog.ri <<'EOF'
module blog

import site::{run}

pub def home : Int32
  run
end

spec 1.1
  get("/") == 200
end
EOF
"$IYI" test blog.ri > g.out 2>&1
[ $? = 0 ] && fail "(g) an undefined get passed"
has g.out "web/spec defines \`get\`; add \`import web/spec::*\` after the first \`spec\` block"
cd ..

[ "$failed" = 0 ] && echo "spec_blocks_lock: ok"
exit "$failed"
