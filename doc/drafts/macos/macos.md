# Draft: ris programs on macOS arm64

## Change

SPEC 7.1 today says:

    Programs build only for Linux x86_64 and aarch64; other targets fail at
    compile time.

It becomes:

    Programs build only for Linux x86_64 and aarch64 and macOS arm64; other
    targets fail at compile time.

The HTTP rule in SPEC 5 gains: "On macOS N is 1: it gives a SO_REUSEPORT
port's connections to one listener; more is refused." No tape rule changes.
Returning pages to the OS is unmeasured on macOS (below). README,
CONTRIBUTING, TODO, UPSTREAM, doc/MESSAGES.md and install_ris.sh's refusal
follow. macOS x86_64 stays refused.

## Problem

An agent or a person on an Apple Silicon Mac cannot run a ris program at
all without a Linux VM. The first build fails with the 7.1 refusal.

## What exists

Branch `macos-arm64`, seven commits, 17 files, +253/-80. The code was
written as a trial before this review, against AGENTS.md's order, so this
review may send it back; nothing is on main yet.

* `src/iyi/heap.iyi`, `src/compiler/iyi/program.cr`: the target gates.
* `src/iyi/region_none.iyi`, `src/iyi/region.iyi`: mapping through
  libSystem's `mmap`, `munmap`, `madvise`, `mprotect`, not raw syscalls
  (Darwin has no stable syscall ABI). 16 KiB page masks; `MADV_FREE` where
  Linux has `MADV_DONTNEED`. `MAP_NORESERVE` means nothing on Darwin.
* `src/iyi/concurrency.iyi`: kqueue where Linux has epoll. A change record
  for `kevent` is written on the stack by `__iyi_kevent_change`.
* `src/std/socket.iyi`: the connect race on kqueue.
* `src/std/udp.iyi`: SO_SNDBUF 65535, Darwin's default caps a datagram at
  about 9 KiB.
* `src/std/debug.iyi`: reads DWARF through a small marked `open_dwarf`.
* `test/ris/check.sh`: debug regexes accept mangled frame names, on Linux
  too. `test/ris/check_parallel.py`: `RIS_CHECK_SKIP`, a regex of checks.
* `.github/workflows/ris-macos.yml`: macos-15, Homebrew LLVM 23.1.4 and
  Crystal, `make ris`, samples, then check.sh in shards.

## Evidence

The trial, `f42ef15ed`: all macOS jobs green (actions run 41716687667), Linux
x86_64 check.sh green. The final tree's runs are in its commit's checks: both
Linux targets and macOS must pass before main.

## What the checks do not prove

Four checks are skipped on macOS, because they read `/proc`:

* `scope_frees.ri`, `fibers/spares.ri`: measure pages returned to the OS. So
  this is unmeasured there; `MADV_FREE` is lazy and resident size may stay
  high until the system needs pages.
* `file_copy_to.ri` (and its missing-file block, which the regex also takes),
  `tls_session_tickets.ri`.

Other gaps: the checks use a non-release compiler; only `respond.ri` was
built `--release`. Timing was not measured. A backtrace's frame names are
mangled, its file and line right. A large reservation without `MAP_NORESERVE`
is untested beyond GitHub's runner. A Mac's default of 256 descriptors is
lower than CI's `ulimit -n 10240`; nothing in src/ raises it.

## Scope of "supported"

Source build only: `make install_ris` with Crystal 1.21 and LLVM 23 or newer
(Homebrew's in CI). check.sh also needs Homebrew's bash and coreutils first on
PATH, and pkgconf. No tarball: `scripts/build-static-llvm.sh` failed on the Mac,
`ris-release.yml` stays Linux and `install_ris.sh` points to the source build.
Pushes to main and pull requests run `ris-macos.yml`; it exits with check.sh's
status.

## Alternatives

* Stay Linux-only, Mac users use a VM or container: rejected by the owner,
  who asked for macOS on main. The diff is small; the recurring cost is a CI
  job on every commit and the macOS list in TODO.md.
* Keep the branch out of main until after release 0.1.0: rejected, the owner
  asked for it now. `8abafc514` stays taggable as a Linux-only 0.1.0.
* Refuse HTTP on macOS altogether: rejected. One connection at a time is what
  it really does, and it is enough to develop a server.
* A shared listener on macOS: rejected by doc/MESSAGES.md and SPEC 5's rule
  that a socket never crosses tasks.
* Add macOS x86_64 too: rejected. Apple stopped selling it, no runner
  is planned, and 7.1 should promise only what CI runs.
* Add a tarball and installer now: postponed; needs a static LLVM on Mac.

## Non-goals

No Windows, no macOS x86_64, no iOS. No change to any tape rule. No new
annotation. The compiler executable keeps its GC on macOS as on Linux.

## Risks

* Shared runtime files changed (`concurrency.iyi`, `region.iyi`,
  `prelude.iyi`, `socket.iyi`): a Linux regression. Mitigated by Linux
  check.sh on both arches before main.
* Agents read `MADV_FREE` residue as a leak on macOS: read `RIS_TAPE_STATS`,
  tape use, rather than resident size there.
* One more CI target slows every commit by a macOS job.
* A promise in SPEC with skipped checks: agents assume parity. TODO.md lists
  them.

## Follow-up work

TODO.md, section "macOS arm64", in the same commit as SPEC.

## Review

EGM stages zoom out, comprehension and critic, on code already written, so
the order CONTRIBUTING asks was not kept: stated in the changelog. No stage 9:
the code exists and was checked instead. Reports were worksheets, not kept.

* Blocker, fixed: "no other rule changes" was false. A failed run's 36 replies
  on three listeners all came from one worker, so one held connection stalls
  the rest and N does not limit connections. HTTP's default N is 1 on macOS,
  a larger N is refused naming the safe form, and http_prefork.py now runs
  there with N = 1 and checks the refusal.
* Fixed: CI ignored check.sh's status; socket_race and system never ran on
  macOS; the backtrace regex was loosened on Linux too; the target refusal
  came 3,000 prelude lines in and had no gate; llvm was not installed by name;
  the trial's workflow and installer text did not match this draft.
* Answered, not fixed: `MADV_FREE` may never show as pages returned, so a
  `task_info` port may need `MADV_FREE_REUSABLE` or `mmap` over the range
  (TODO.md). `flag?(:linux) || flag?(:darwin)` repeats instead of one named
  predicate: left, two targets do not need it. Fiber stacks keep 4096 masks;
  the guard rounds up to 16 KiB, which costs stack and not safety.
* Timing: merging before the tag was the owner's call. Linux aarch64 and
  x86_64 CI on the final tree are a condition of merging.
