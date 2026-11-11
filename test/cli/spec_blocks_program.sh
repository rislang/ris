#!/usr/bin/env bash
# Spec blocks: `tmp` and the program (doc/drafts/spec-blocks/
# spec-blocks.md 5.5, 5.7, 5.16; step 4, D16-D18).
#
#     bash test/cli/spec_blocks_program.sh
#
# (a) a module block writes, reads and lists files in `tmp`, and the
# directory is gone after the run; (b) a CLI program file: `demo ==
# "...\n"`, a status, stdin, env, and a failing line that prints stdout,
# stderr and status; (c) a background program: start, wait_for a ready
# line, write to its stdin, wait_for the echo, and no process of it left;
# (d) a kept def using a name only top-level code sets is refused; (e)
# locals named `tmp` or like the module are refused, and a `*/spec`
# import above the section; (f) a plain `ris build` binary has no
# RisRun or RisProcess symbol.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
IYI="${IYI:-$REPO/bin/ris}"
case "$IYI" in /*) ;; *) IYI="$PWD/$IYI" ;; esac
mkdir -p "$REPO/test/cli/.work"
WORK="$(mktemp -d "$REPO/test/cli/.work/XXXXXX")"
TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"
export TMPDIR
trap 'pkill -f "$WORK/" 2>/dev/null; rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1

failed=0
fail() { echo "FAIL: $*"; failed=1; }
has() { grep -qF -- "$2" "$1" || { fail "$1 lacks: $2"; cat "$1"; }; }

cat > SPEC.md <<'EOF'
# Demo

## 1. Files

* 1.1 A note is kept in a file.
* 1.2 Running demo prints a greeting.
* 1.3 A wrong argument exits 2.
* 1.4 The server echoes its input.
EOF

# (a) tmp in a module file.
cat > notes.ri <<'EOF'
module notes

pub def keep(dir : String, text : String) : Nil
  File.write(dir + "/note.txt", text)
end

spec 1.1
  keep(tmp.path, "hi")
  tmp.file("sub/deep/a.txt", "x")
  tmp.read("note.txt") == "hi"
  tmp.read("sub/deep/a.txt") == "x"
  tmp.children == ["note.txt", "sub"]
  tmp.children("sub") == ["deep"]
  File.write((Program.env("TMPDIR") || "") + "/../seen", tmp.path)
end
EOF
"$IYI" test notes.ri > a.out 2>&1
[ $? = 0 ] || { fail "(a) tmp block did not pass"; cat a.out; }
has a.out "ok  spec 1.1"
seen="$(cat "$WORK/seen" 2>/dev/null)"
[ -n "$seen" ] || fail "(a) the block did not record tmp.path"
[ -n "$seen" ] && [ -e "$seen" ] && fail "(a) $seen is left after the run"

# (b) a CLI program.
cat > demo.ri <<'EOF'
module demo

name = Program.args[0]? || "demo"
if name == "x"
  STDERR.puts "bad argument"
  exit 2
end
extra = Program.env("GREETING") || "hello"
input = STDIN.read_all
puts extra + " from " + name + input

spec 1.2
  demo == "hello from demo\n"
  out = demo("ann")
  out.stdout == "hello from ann\n"
  out.status == 0
  demo(stdin: "!") == "hello from demo!\n"
  demo(env: {"GREETING" => "hi"}) == "hi from demo\n"
end

import std/regex::{Regex}

spec 1.3
  demo("x").status == 2
  demo("x").stderr =~ %r{bad argument}
end

spec 1.2
  demo("x") == "hello from x\n"
end
EOF
"$IYI" test demo.ri > b.out 2>&1
[ $? = 1 ] || { fail "(b) the failing block did not fail the run"; cat b.out; }
grep -c "^ok  spec 1\.[23]" b.out | grep -qx 2 || { fail "(b) two blocks pass"; cat b.out; }
has b.out 'demo("x") == "hello from x\n"'
has b.out 'status: 2'
has b.out 'stdout: ""'
has b.out 'stderr: "bad argument\n"'

# (c) a background program.
cat > echo.ri <<'EOF'
module echo

puts "ready"
STDOUT.flush
while line = STDIN.gets
  puts "echo: " + line
  STDOUT.flush
end

import std/regex::{Regex}

spec 1.4
  server = echo.start
  server.wait_for(%r{ready}, 5)
  server.write("ping\n")
  server.wait_for(%r{echo: ping}, 5)
  server.status.nil?
  File.write((Program.env("TMPDIR") || "") + "/../pid", tmp.path)
end
EOF
"$IYI" test echo.ri > c.out 2>&1
[ $? = 0 ] || { fail "(c) background block did not pass"; cat c.out; }
has c.out "ok  spec 1.4"
pgrep -f "$WORK/tmp/ris-program" > c.ps &&
  fail "(c) a process of echo is left after the run: $(cat c.ps)"
seen="$(cat "$WORK/pid" 2>/dev/null)"
[ -n "$seen" ] && [ -e "$seen" ] && fail "(c) $seen is left after the run"

# (d) a kept def using a dropped name.
cat > d.ri <<'EOF'
module d

CONFIG = "x" + "y"

private def show : String
  CONFIG
end

puts show

spec 1.2
  d == "xy\n"
end
EOF
"$IYI" test d.ri > d.out 2>&1
[ $? = 0 ] && fail "(d) a def using a dropped name passed"
has d.out "\`CONFIG\` is set by d.ri's top-level code, which spec blocks do not run"

# (e) locals named tmp or like the module; a */spec import above.
cat > e1.ri <<'EOF'
module e1

pub def one : Int32
  1
end

spec 1.1
  tmp = 3
  one == 1
end
EOF
"$IYI" test e1.ri > e1.out 2>&1
[ $? = 0 ] && fail "(e) a local named tmp passed"
has e1.out "\`tmp\` is the block's temporary directory in a spec block; rename the local"

cat > e2.ri <<'EOF'
module e2

puts "hi"

spec 1.2
  e2 = 1
  e2 == 1
end
EOF
"$IYI" test e2.ri > e2.out 2>&1
[ $? = 0 ] && fail "(e) a local named like the module passed"
has e2.out "\`e2\` runs the program in a spec block; rename the local"

mkdir -p web
printf 'module web/spec\n\npub def get : Int32\n  1\nend\n' > web/spec.ri
cat > e3.ri <<'EOF'
module e3

import web/spec

puts "hi"
EOF
"$IYI" build e3.ri -o e3 > e3.out 2>&1
[ $? = 0 ] && fail "(e) a */spec import above the section built"
has e3.out "web/spec is test vocabulary; import it after the first \`spec\` block"

# (f) the plain build carries no test-only type.
"$IYI" build demo.ri -o demo_plain > f.out 2>&1 || { fail "(f) plain build"; cat f.out; }
if [ -f demo_plain ]; then
  if strings demo_plain | grep -qE "RisRun|RisProcess|RisTmp"; then
    fail "(f) the plain binary names a test-only type"
  fi
  ./demo_plain ann < /dev/null | grep -qx "hello from ann" || fail "(f) plain binary"
fi

[ "$failed" = 0 ] && echo "spec_blocks_program: ok"
exit "$failed"
