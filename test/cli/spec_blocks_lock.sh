#!/usr/bin/env bash
# spec: 6.7@436841dc, 6.8@82707d6b
# Spec blocks: `ris spec` on blocks, .spec.lock, the clause label and the
# hint for a missing package spec import (doc/drafts/spec-blocks/
# spec-blocks.md 5.9, 5.10, 5.14-5.16; step 6).
#
#     bash test/cli/spec_blocks_lock.sh
#
# A block in src/ covers its clause; .spec.lock holds the reviewed hash, so
# editing the clause fails `ris check spec` until `ris spec ack` (a stale
# old tag `@V` no longer counts); an orphan lock line fails; `ris check
# --fix` (the suite and its spec step) writes and refreshes labels, cut at a word with `…` within 80
# columns; a stale label fails; a fresh label does not clear "to review";
# `ris spec ack --from-tags` seeds the lock, and ris's own `ris check
# spec` is green; a block calling a name web/spec defines, in a file
# reaching web through site, is told the import to add.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RIS="${RIS:-$REPO/bin/ris}"
case "$RIS" in /*) ;; *) RIS="$PWD/$RIS" ;; esac
mkdir -p "$REPO/test/cli/.work"
WORK="$(mktemp -d "$REPO/test/cli/.work/XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

failed=0
fail() { echo "FAIL: $*"; failed=1; }
has() { grep -qF -- "$2" "$1" || { fail "$1 lacks: $2"; cat "$1"; }; }
version() { "$RIS" spec "$1" | head -1 | cut -d' ' -f1; }
changelog() {
  printf '## 2026-01-0%s · %s %s\n\nWhy.\n\n' "$1" "$(version 1.1)" \
    "$(version 1.2)" >> CHANGELOG.md
}

cat > SPEC.md <<'EOF'
# Demo

## 1. Posts

* 1.1 A post needs a title.
* 1.2 A post's slug is its title in lower case, with every run of spaces
  and punctuation turned into one dash and no dash at either end of it.
EOF
echo "# Changelog" > CHANGELOG.md
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
"$RIS" spec > a.out 2>&1
has a.out "1.1   to review     2"
"$RIS" check spec > a2.out 2>&1
[ $? = 0 ] && fail "(a) unreviewed blocks passed check spec"
has a2.out "1.1 has proofs not reviewed yet"
has a2.out "review src/post.ri:7"

# (b) ack writes .spec.lock and clears it despite the stale tag.
"$RIS" spec ack 1 > b.out 2>&1 || { fail "(b) ack"; cat b.out; }
grep -qx "1.1 $(version 1.1 | cut -d@ -f2)" .spec.lock || fail "(b) no 1.1 line"
"$RIS" check spec > b2.out 2>&1 || { fail "(b) check after ack"; cat b2.out; }
has b2.out "1 ok, 1 todo, 0 to review"

# (c) editing the clause fails until ack.
sed -i 's/needs a title\./needs a title of one letter or more./' SPEC.md
changelog 2
"$RIS" check spec > c.out 2>&1
[ $? = 0 ] && fail "(c) an edited clause passed"
has c.out "1.1 changed since its proofs were reviewed"
"$RIS" spec ack 1.1 > /dev/null 2>&1
"$RIS" check spec > c2.out 2>&1 || { fail "(c) check after re-ack"; cat c2.out; }

# (d) an orphan lock line fails; any ack drops it.
echo "9.9 abcdef12" >> .spec.lock
"$RIS" check spec > d.out 2>&1
[ $? = 0 ] && fail "(d) an orphan lock line passed"
has d.out ".spec.lock holds 9.9, which is no clause of the spec"
"$RIS" spec ack 1.1 > /dev/null 2>&1
grep -q "^9.9" .spec.lock && fail "(d) ack kept the orphan"

# (e) labels: --fix writes them; the long one is cut within 80 columns.
"$RIS" check spec --fix > e.out 2>&1 || { fail "(e) check --fix"; cat e.out; }
grep -qx "spec 1.1  # A post needs a title of one letter or more." src/post.ri ||
  fail "(e) 1.1 label not written"
long="$(grep '^spec 1.2' src/post.ri)"
case "$long" in
  "spec 1.2  # A post's slug is its title in lower case,"*"…") ;;
  *) fail "(e) 1.2 label not cut with …: $long" ;;
esac
[ "$(printf '%s' "$long" | LC_ALL=C.UTF-8 wc -m)" -le 80 ] || fail "(e) label over 80 columns"
"$RIS" check spec > e2.out 2>&1 || { fail "(e) check after --fix"; cat e2.out; }
sed -i 's/^spec 1.1  # .*/spec 1.1  # A post needs nothing./' src/post.ri
"$RIS" check spec > e3.out 2>&1
[ $? = 0 ] && fail "(e) a stale label passed"
has e3.out "the label of spec 1.1 at src/post.ri:7 differs from SPEC.md"
has e3.out "run \`ris check --fix\`"
# The command the message names fixes it: the whole suite's --fix reaches
# the spec step (its exit is the other steps' business).
"$RIS" check --fix > e3b.out 2>&1
grep -qx "spec 1.1  # A post needs a title of one letter or more." src/post.ri ||
  { fail "(e) ris check --fix did not refresh the label"; cat e3b.out; }
# A clause edit: --fix refreshes the label, but the clause stays to review.
sed -i 's/one letter or more\./a letter or more./' SPEC.md
changelog 3
"$RIS" check spec --fix > e4.out 2>&1
[ $? = 0 ] && fail "(e) a fresh label cleared to review"
grep -qx "spec 1.1  # A post needs a title of a letter or more." src/post.ri ||
  fail "(e) 1.1 label not refreshed"
has e4.out "1.1 changed since its proofs were reviewed"

# (f) --from-tags seeds the lock from matching tags.
mkdir f && cd f
printf '# Demo\n\n## 1. A\n\n* 1.1 One.\n' > SPEC.md
printf '# spec: 1.1@%s\nputs 1\n' "$("$RIS" spec 1.1 | head -1 | cut -d@ -f2 | cut -d' ' -f1)" > x_test.ri
mkdir test && mv x_test.ri test/
"$RIS" spec ack --from-tags > f.out 2>&1 || { fail "(f) --from-tags"; cat f.out; }
grep -q "^1.1 " .spec.lock || fail "(f) --from-tags wrote no 1.1 line"
cd ..
(cd "$REPO" && "$RIS" check spec > "$WORK/f2.out" 2>&1) ||
  { fail "(f) ris's own check spec"; tail -5 f2.out; }
[ -f "$REPO/.spec.lock" ] || fail "(f) ris has no .spec.lock"

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
"$RIS" test blog.ri > g.out 2>&1
[ $? = 0 ] && fail "(g) an undefined get passed"
has g.out "web/spec defines \`get\`; add \`import web/spec::*\` after the first \`spec\` block"
cd ..

# (h) The spec's changes are the changelog: CHANGELOG.md, a `###` entry
# under a release heading counts; a left-over SPEC_CHANGELOG.md or
# spec.lock (now .spec.lock) fails.
mkdir h && cd h
printf '# Demo\n\n## 1. A\n\n* 1.1 One.\n' > SPEC.md
printf 'module h\n\npub def one : Int32\n  1\nend\n\nspec 1.1\n  one == 1\nend\n' > h.ri
"$RIS" spec ack 1.1 > /dev/null 2>&1
printf '# Changelog\n\n## 0.2.0 (unreleased)\n\n### 2026-01-01 · %s\n\nWhy.\n' \
  "$(version 1.1)" > CHANGELOG.md
"$RIS" check spec > h.out 2>&1 || { fail "(h) a ### entry under a release"; cat h.out; }
printf '# Changelog\n\n## 0.2.0\n\n%s\n' "$(version 1.1)" > CHANGELOG.md
"$RIS" check spec > h2.out 2>&1
[ $? = 0 ] && fail "(h) a version under a release heading alone counted"
has h2.out "no CHANGELOG.md entry records 1.1@"
printf '# Changelog\n\n## 2026-01-01 · %s\n\nWhy.\n' "$(version 1.1)" > CHANGELOG.md
echo "# Old" > SPEC_CHANGELOG.md
"$RIS" check spec > h3.out 2>&1
[ $? = 0 ] && fail "(h) a left-over SPEC_CHANGELOG.md passed"
has h3.out "SPEC_CHANGELOG.md is the old name"
rm SPEC_CHANGELOG.md
mv .spec.lock spec.lock
"$RIS" check spec > h4.out 2>&1
[ $? = 0 ] && fail "(h) a left-over spec.lock passed"
has h4.out "spec.lock is the old name of .spec.lock"
cd ..

# (i) standards proofs require a nonempty leading module header.
mkdir header
cd header || exit 1
printf '# Demo\n\n## 8. Library\n\n* 8.1 Follow the named standard.\n' > SPEC.md
printf 'module codec\n\nspec 8.1\n  true\nend\n' > codec.ri
printf '# Changelog\n\n## 2026-11-11 · %s\n\nWhy.\n' "$(version 8.1)" > CHANGELOG.md
"$RIS" spec ack 8.1 > /dev/null 2>&1
"$RIS" check spec > missing.out 2>&1
[ $? = 0 ] && fail "(i) missing standard header passed"
has missing.out 'add `# standard: ...` to the module header'
# A comment below the module header does not count as a leading header.
sed -i '2i# standard: RFC 4648' codec.ri
"$RIS" check spec > late.out 2>&1
[ $? = 0 ] && fail "(i) misplaced standard header passed"
sed -i '2d;1i# standard: ' codec.ri
"$RIS" check spec > blank.out 2>&1
[ $? = 0 ] && fail "(i) empty standard header passed"
sed -i '1c# standard: RFC 4648' codec.ri
"$RIS" check spec > valid.out 2>&1 || fail "(i) valid header refused"
cd ..

[ "$failed" = 0 ] && echo "spec_blocks_lock: ok"
exit "$failed"
