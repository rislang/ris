#!/usr/bin/env bash
# A name a selective import wrote out beats a module named by a file path.
#
#     bash test/cli/import_beats_module_name.sh
#
# In project `blog`, `store.ri` is module `Blog::Store`. blog.ri, the root
# module, wrote `import store::{Store}` for the class `Store` in it, and
# `Store.new` met "undefined method 'new' for Blog::Store:Module": the
# path's module, a child of `Blog`, was found before the import, at the
# top and from inside a class of blog.ri. site.ri,
# a sibling module, got the class. Found in the blog-demo rispack.

set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RIS="${RIS:-$REPO/bin/ris}"
case "$RIS" in /*) ;; */*) RIS="$PWD/$RIS" ;; esac
mkdir -p "$REPO/test/cli/.work"
WORK="$(mktemp -d "$REPO/test/cli/.work/XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export RIS_PATH="$REPO/src"

printf 'module blog\n' >"$WORK/ris.mod"
cat >"$WORK/store.ri" <<'EOF'
module store

pub class Store
  def initialize(@name : String)
  end

  def name : String
    @name
  end
end
EOF
cat >"$WORK/blog.ri" <<'EOF'
module blog

import store::{Store}

class Factory
  def self.name : String
    Store.new("posts").name
  end
end

store = Store.new("posts")
puts store.name
puts Factory.name
EOF

if ! out=$(cd "$WORK" && "$RIS" run blog.ri 2>&1); then
  echo "  FAIL import beats module name: $out"
  exit 1
fi
# A pre-existing warning about `pub class Store` may come first.
if [ "$(printf '%s\n' "$out" | tail -2 | tr '\n' ' ')" != "posts posts " ]; then
  echo "  FAIL import beats module name: printed $out"
  exit 1
fi
echo "  ok   import beats module name"
