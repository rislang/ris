#!/usr/bin/env bash
# Drives test/cli/parallel_exercise.ri: tasks across cores (iyi SPEC III.4.13).
#
#     bash test/cli/parallel_exercise.sh
#
# Runtime properties and failure proofs, because a gate that
# cannot fail is not a gate:
#
#   1. The exercise holds every property, plain and --release: parallel
#      tasks start on the pool and on more than one worker, each stays on
#      the thread that started it, a thousand run exactly once, an atomic
#      count loses nothing, board messages cross threads once each
#      and in each sender's order, a cancel reaches a task asleep, parked
#      on a board take, or still waiting in the pool, a panic stops at the
#      task's boundary, idle workers steal, collections keep the workers'
#      lists, and the typed group answers.
#   2. The binary keeps the dependency floor the concurrency gate holds,
#      plus `environ`, the C runtime's table `RIS_WORKERS` is read from.
#   Timings live in the parallel measurement under test/speed/.
#   4. A deadlock across threads - a parallel task waiting on a board take
#      nobody sends on - is named, not hung.
#   5. `Share` gates the parallel block at compile time: a captured
#      `Array`, a local assigned after the spawn, and
#      a loop's local are refused, each by name.
#   6. Failure proofs against broken copies of the runtime, each caught at
#      the named check: a cross-thread wake that does not ring (a lost
#      wakeup), a steal that leaves the task in its victim's queue (a task
#      handed out twice), a cancel that is never delivered to the thread a
#      sleeping task is on, and a cancel that skips tasks still waiting in
#      the pool (a cancelled task run as if it were not); and the race
#      step's add made a plain load and store, which loses adds only when
#      tasks really run at the same instant.
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RIS="${RIS:-$REPO/bin/ris}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ris-gate.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT)
    REPO="$(cygpath -m "$REPO")"
    WORK="$(cygpath -m "$WORK")"
    ;;
esac

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT) PSEP=';' ;;
  *) PSEP=':' ;;
esac

. "$REPO/test/cli/floor_base.sh"

cd "$WORK" || exit 1

step() { echo "== $1"; }

# The cores this process may run on, as the pool counts them.
cores() {
  case "$(uname -s)" in
    Darwin) sysctl -n hw.ncpu ;;
    MINGW* | MSYS* | CYGWIN* | Windows_NT) echo "${NUMBER_OF_PROCESSORS:-1}" ;;
    *) nproc ;;
  esac
}
CORES="$(cores)"

# ── 1. The exercise, twice ────────────────────────────────────────────────
for build in plain release; do
  step "every property, $build build"
  flag=""
  [ "$build" = release ] && flag="--release"
  if ! "$RIS" build $flag "$REPO/test/cli/parallel_exercise.ri" -o "exercise-$build" > "build-$build.log" 2>&1; then
    echo "build failed:"; tail -20 "build-$build.log"; exit 1
  fi
  timeout -k 5 600 "./exercise-$build" > "answers-$build.txt" 2>&1
  code=$?
  if [ "$code" -ne 0 ] || ! grep -q 'every property held' "answers-$build.txt"; then
    echo "the exercise failed (exit $code):"; cat "answers-$build.txt"; exit 1
  fi
  if grep -q 'a done fiber was scheduled' "answers-$build.txt"; then
    echo "the exercise scheduled a finished fiber:"; cat "answers-$build.txt"; exit 1
  fi
  grep -v '^ris: panic: parallel boom' "answers-$build.txt" | sed 's/^/  /'
done

# ── 2. The floor ──────────────────────────────────────────────────────────
# What the pool costs each platform, by name. Its workers are the
# runtime's own threads, so it pays what a thread pays and nothing else:
#
#   Linux    nothing of the pool's own: a worker is a thread, which in ris
#            is glibc's (`pthread_create`, the retired GC gates), the
#            stop by `tgkill`, the doorbell by `eventfd2`, both syscalls.
#            `environ` is the one name, the C runtime's table
#            `RIS_WORKERS` is read from through `Program.env`.
#   darwin   the runtime's list (the retired GC gates spells it out),
#            the thread floor's names a started thread costs -
#            `pthread_create`, `pthread_kill` and `sigaction` for the
#            thread and the stop, `pipe`/`read`/`write` for the stop's
#            park, and `close` for a retiring thread's kqueue
#            (`IyiScheduler.retire_thread`, linked with every thread
#            body) - and `_environ` for `RIS_WORKERS`. The doorbell is an
#            `EVFILT_USER` change through `kevent`, already on the list,
#            and the core count is `sysctlbyname("hw.ncpu")`, also already
#            there for the marker. No `pthread_join`: nothing joins a
#            worker.
#   Windows  kernel32 and the C runtime's DLLs; the doorbell is
#            `PostQueuedCompletionStatus`, kernel32's.
step "dependency floor: the pool costs what a thread costs, and the environment it reads RIS_WORKERS from"
NM=""
command -v nm >/dev/null 2>&1 && NM=nm
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN* | Windows_NT)
    DUMPBIN="$(find_dumpbin || true)"
    if [ -z "$DUMPBIN" ]; then
      echo "  no dumpbin here, so the import floor is not measured"
    else
      dlls="$(pe_dlls exercise-plain.exe)"
      [ -n "$dlls" ] || { echo "dumpbin read no import table out of the exercise"; exit 1; }
      extra="$(extra_dlls "$FLOOR_DLLS_RUNTIME" "$dlls")"
      if [ -n "$extra" ]; then
        echo "the pool moved the Windows floor: the exercise imports $(echo $extra)"; exit 1
      fi
      echo "  imports: $(echo $dlls)"
    fi
    ;;
  Darwin)
    [ -n "$NM" ] || { echo "no nm here, so the symbol floor is not measured"; exit 1; }
    runtime='___error __dyld_get_image_header __dyld_get_image_vmaddr_slide __tlv_bootstrap _backtrace _backtrace_symbols_fd _clock_gettime_nsec_np _exit _kevent _kqueue _mmap _mprotect _munmap _pthread_create _pthread_get_stackaddr_np _pthread_self _sigaction _sigaltstack _sysctlbyname _write'
    thread='_close _pipe _pthread_kill _read'
    pool='_environ'
    allowed="$(printf '%s\n' $runtime $thread $pool | sort -u)"
    for bin in exercise-plain exercise-release; do
      found="$("$NM" -u "$bin" | sed -e 's/^ *//' | awk '{ print $NF }' | sort -u)"
      extra="$(comm -13 <(echo "$allowed") <(echo "$found"))"
      if [ -n "$extra" ]; then
        echo "$bin asks libSystem for more than the list:"
        echo "$extra" | sed 's/^/  /'
        exit 1
      fi
    done
    echo "  the runtime's names, a thread's ($(echo $thread)) and $pool, and nothing else, plain and release"
    ;;
  *)
    [ -n "$NM" ] || { echo "no nm here, so the symbol floor is not measured"; exit 1; }
    for bin in exercise-plain exercise-release; do
      added="$("$NM" -u "$bin" |
        sed -e 's/^ *[wU] *//' -e 's/@.*$//' |
        grep -v -E '^(_ITM_deregisterTMCloneTable|_ITM_registerTMCloneTable|__cxa_finalize|__gmon_start__|__libc_start_main|_PROCEDURE_LINKAGE_TABLE_|environ|__environ)$' |
        grep -v -E '^(pthread_create|pthread_join|pthread_attr_init|pthread_attr_setstack|pthread_attr_destroy)$' |
        grep -cv '^\s*$')"
      if [ "$added" -ne 0 ]; then
        echo "the pool put $added undefined symbols on $bin's link line:"; "$NM" -u "$bin"; exit 1
      fi
    done
    echo "  the C runtime template's names, glibc's thread and environ, which RIS_WORKERS is read through, plain and release: the pool itself is raw syscalls"
    ;;
esac

# ── 4. A deadlock across threads is named ────────────────────────────────
step "a deadlock across threads is a diagnosis, not a hang"
cat > paralleldeadlock.ri <<'RIS'
module paralleldeadlock

record Never, n : Int32

group do |g|
  g.spawn_parallel do
    RisBoard.take(Never)
    0
  end
end
puts "the group ended"
RIS
if ! "$RIS" build paralleldeadlock.ri -o paralleldeadlock > build-deadlock.log 2>&1; then
  echo "the deadlock program failed to build:"; tail -20 build-deadlock.log; exit 1
fi
timeout -k 5 30 ./paralleldeadlock > deadlock.txt 2>&1
code=$?
if [ "$code" -ne 1 ] || ! grep -q 'deadlock: every fiber is blocked' deadlock.txt; then
  echo "a deadlock across threads exited $code (124 is a hang):"; cat deadlock.txt; exit 1
fi
echo "  exits 1: $(grep -m1 'deadlock' deadlock.txt)"

# ── 5. Share gates the parallel block ─────────────────────────────────────
step "Share gates what a parallel task's block captures"
refused() { # name, expected text, program body
  printf 'module %s\n\n%s\n' "$1" "$3" > "$1.ri"
  if "$RIS" build "$1.ri" -o "$1" > "$1.log" 2>&1; then
    echo "a program that must not compile compiled: $1"; cat "$1.ri"; exit 1
  fi
  if ! grep -qF "$2" "$1.log"; then
    echo "$1 was refused, but not for the reason:"; cat "$1.log"; exit 1
  fi
  echo "  refused: $(grep -m1 -F "$2" "$1.log" | sed 's/^ *//' | cut -c1-150)"
}
refused shares_array 'this block becomes a proc, which may run after the tape block that made `items : Array(Int32)` has ended' '
items = [1, 2, 3]
group do |g|
  g.spawn_parallel { items.size }
end'
refused assigns_after '`count` is assigned here, after the task was spawned' '
def launch(g : IyiGroup) : Nil
  count = 1
  g.spawn_parallel { count + 1 }
  count = 2
end

group do |g|
  launch(g)
end'
refused loop_local 'in a loop or a block that spawns the task again' '
group do |g|
  i = 0
  while i < 4
    seed = i * 10
    g.spawn_parallel { seed + 1 }
    i = i + 1
  end
end'

# ── 6. Failure proofs: broken copies of the runtime ──────────────────────
# Each a copy of src/ris with one line of concurrency.ri changed, built
# against through RIS_PATH; nothing in the tree is touched.
broken() { # name, awk program
  mkdir -p "$1/ris"
  cp "$REPO"/src/ris/*.ri "$1/ris/"
  awk "$2" "$REPO/src/ris/concurrency.ri" > "$1/ris/concurrency.ri"
  if cmp -s "$1/ris/concurrency.ri" "$REPO/src/ris/concurrency.ri"; then
    echo "the awk for $1 found nothing to change"; exit 1
  fi
  if ! RIS_PATH="$WORK/$1${PSEP}$REPO/src" "$RIS" build "$REPO/test/cli/parallel_exercise.ri" -o "$1-run" > "build-$1.log" 2>&1; then
    echo "the broken copy $1 failed to build:"; tail -20 "build-$1.log"; exit 1
  fi
}
caught() { # name, expected FAIL text, step arguments...
  local name="$1" want="$2"
  shift 2
  timeout -k 5 120 "./$name-run" "$@" > "$name.txt" 2>&1
  local code=$?
  if [ "$code" -ne 1 ] || ! grep -qF "$want" "$name.txt"; then
    echo "the broken copy $name was not caught at \"$want\" (exit $code):"; tail -20 "$name.txt"; exit 1
  fi
  echo "  exits 1 at \"$(grep -m1 -F "$want" "$name.txt" | sed 's/^FAIL: //; s/^ris: panic: //')\""
}

step "failure proof: a cross-thread wake that does not ring is a lost wakeup"
broken lostwake '/def self.ready\(fiber/ { inready = 1 } inready && /^    ring\(home\)$/ { print "    # the doorbell, not rung"; inready = 0; next } { print }'
caught lostwake 'placement: still waiting after 5000 ms' placement --watch=5000

step "failure proof: a steal that leaves the task in its victim's queue hands it out twice"
broken duplicate '/^          victim.pool_head = fiber.next_run$/ { next } /^          victim.pool_tail = nil if victim.pool_head.is_a\?\(Nil\)$/ { next } { print }'
caught duplicate 'the pool handed one parallel task to a worker twice' steal

step "failure proof: a cancel never delivered to a sleeping task's thread"
broken undelivered '/^    return if fiber.cancel_posted$/ { print "    return"; next } { print }'
caught undelivered 'cancel: still waiting after 5000 ms' cancel --watch=5000

step "failure proof: a cancel that skips tasks waiting in the pool runs them uncancelled"
broken unflagged '/def self.cancel\(fiber/ { incancel = 1 } incancel && /^    fiber.cancelled = true$/ { print "    fiber.cancelled = true unless fiber.home.is_a?(Nil)"; incancel = 0; next } { print }'
caught unflagged 'tasks waiting in the pool ran uncancelled' cancel --watch=60000

step "failure proof: a plain add loses counts when tasks run at the same instant"
if [ "$CORES" -lt 2 ]; then
  echo "  one core here: two tasks cannot be at the same instant, so the proof is not run"
else
  if ! "$RIS" build --release -Dparallel_plain_add "$REPO/test/cli/parallel_exercise.ri" -o plainadd > build-plainadd.log 2>&1; then
    echo "the plain-add build failed:"; tail -20 build-plainadd.log; exit 1
  fi
  timeout -k 5 120 ./plainadd race > plainadd.txt 2>&1
  code=$?
  if [ "$code" -ne 1 ] || ! grep -q 'increments lost' plainadd.txt; then
    echo "a plain add lost nothing (exit $code), so the race step proves nothing:"; cat plainadd.txt; exit 1
  fi
  echo "  exits 1 at \"$(grep -m1 'increments lost' plainadd.txt | sed 's/^FAIL: //')\""
fi

echo "parallel gate: every property held"
