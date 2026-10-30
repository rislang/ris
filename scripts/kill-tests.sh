#!/usr/bin/env bash
# Kill test processes a finished run left behind: a hung fiber test or a
# server sample can outlive its gate. A process is a test when it is ours,
# not an ancestor of this script, and either runs a binary under .build/
# of this checkout, or runs a binary from a temp or compiler cache
# directory with its working directory in this checkout. A process under
# another live run (make, check.sh, check_parallel.py, spec-par.sh) is left
# alone: that run still owns it. SIGKILL, no grace: our run is over.
#
#   bash scripts/kill-tests.sh        (DRY=1 lists without killing)
set -u
root=$(cd "$(dirname "$0")/.." && pwd -P)
me=$(id -u)

# The parent of PID. /proc/PID/stat's second field is the command name in
# parentheses and may hold spaces ("(Web Content)"), so the fields are
# counted after its closing parenthesis: state, then the parent.
ppid() {
  local stat
  stat=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
  stat=${stat##*) }
  set -- $stat
  echo "$2"
}

# This script and its callers stay alive.
declare -A keep
p=$$
while [ "$p" -gt 1 ]; do
  keep[$p]=1
  p=$(ppid "$p") || break
done

# owned PID: true when an ancestor other than ours is a live run.
owned() {
  local p=$1 cmd
  while [ "$p" -gt 1 ]; do
    p=$(ppid "$p") || return 1
    [ -n "${keep[$p]:-}" ] && return 1
    cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
    case $cmd in
      make\ *|*/make\ *|*check.sh*|*check_parallel.py*|*spec-par.sh*)
        return 0 ;;
    esac
  done
  return 1
}

killed=0
for dir in /proc/[0-9]*; do
  pid=${dir#/proc/}
  [ -n "${keep[$pid]:-}" ] && continue
  [ "$(stat -c %u "$dir" 2>/dev/null)" = "$me" ] || continue
  exe=$(readlink "$dir/exe" 2>/dev/null) || continue
  exe=${exe% (deleted)}
  cwd=$(readlink "$dir/cwd" 2>/dev/null) || cwd=
  case $exe in
    "$root"/.build/*) ;;
    /tmp/*|"${TMPDIR:-/tmp}"/*|"$HOME"/.cache/iyi/*|"$HOME"/.cache/crystal/*)
      case $cwd in "$root"|"$root"/*) ;; *) continue ;; esac ;;
    *) continue ;;
  esac
  owned "$pid" && continue
  echo "kill-tests: $pid $exe"
  [ -n "${DRY:-}" ] || kill -KILL "$pid" 2>/dev/null
  killed=$((killed + 1))
done
[ "$killed" -eq 0 ] || echo "kill-tests: $killed left over"
exit 0
