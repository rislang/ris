# ris tape memory: Goose's data stacks, beside iyi's GC

Decided 2026-10-19: ris takes Goose's memory model whole
([goose_spec.md](https://github.com/aardappel/goose)), not piece by piece,
for its tape types, beside iyi unchanged: `String`, `Array`, `Hash` and
classes stay on the GC heap. [SPEC.md](SPEC.md) is iyi's, unchanged.

## The model
* `tape { }` gives the fiber a block of data stacks, so a reader sees
  where the tape is; outside one a tape value is refused. The outermost
  block hands the stacks back to a shared pool when it ends, so a fiber
  that waits outside one holds none. Nested blocks share them.
* Each stack is a bump pointer over reserved address space, taken lazily,
  small at first and chained to grow; growth never moves.
* Tape types live on them (`Tape::String`, `Writer`, `Tape::Array`,
  `@[OnTape]` structs): variable-size ones on a data stack (buried once
  built), resizable ones each on top of a stack of its own.
* Inside it, every scope that put something there restores its watermark
  on every exit (panic too): a function, a block, a branch, a loop's
  body, an inner `tape`.
* A function takes its stack base as a hidden argument and addresses its
  values at constant offsets above it; a callee starts above its caller's
  watermark (goose_spec App. E). This changes the ABI and `.iyimod`.
* A result is built where the caller wants it (§7.3): `x = f()` on `x`'s
  stack, `v.push(f())` at `v`'s top. Nothing is copied out.
* Non-fixed values are never copied implicitly: bound by reference or
  copied with `copy(x)` (§4.1). Variable-size values do not change once
  built; resizable ones grow (§4.4).
* A fiber of a `group` takes its block from its parent's region: the group
  ends before the parent's scope, so its results stay readable in place.

## Safety
Goose's rules, which hold only together:
* A reference never outlives the variable that owns its target (§9),
  checked statically from its roots; no escape hatch.
* Shrinking (`pop`, `clear`, assignment) only where nothing is rooted in
  the value (§5.1); growth is free, it never moves.
* While a value is built on a stack, nothing else allocates on that one.
* ris's own: a heap object (a class, a class variable, a captured proc)
  holds no reference into a data stack. What it keeps is a heap value,
  copied at the boundary (`to_s`), as today.

## Stages, each measured before the next
1. The engine on today's tape types (`Tape::String`, `Tape::Array`,
   `Writer`, `@[OnTape]`): per-fiber stack blocks, hidden base, watermark
   at every scope, one stack per resizable, results in their destination.
   Gate: `respond`, `bintrees`, `words`, `graph_csr` at Goose's numbers.
2. The checks: Goose's roots and outlives (§9) and shrink rules replace
   TapeLifetimeChecker; the heap rule above.
3. Fibers: a `group`'s children on stacks of its parent's region.
Not a stage: iyi's own types stay as they are; a library moves onto the
tape where it pays, by the rules in CLAUDE.md.

## Today (before stage 1)
One tape per fiber; `tape { }` opens it and only the outermost frees; one
value may grow at its end (TapeLayoutChecker refuses two). Tape values are
`Tape::String`, `Writer`, `Tape::Array`, `Tape::Tree`, `@[OnTape]` structs;
TapeChecker, TapeLifetimeChecker and TapePointerChecker keep them in.

| median of 9, ris-bench | Goose | ris tape | ris heap |
|---|---|---|---|
| respond, 1.6M DTOs | 0.67 s, 2.0 MB | 0.67 s, 1.7 MB | 1.55 s, 7.6 MB |
| bintrees | 0.06 s, 7.9 MB | 0.10 s, 7.1 MB | 0.32 s, 24 MB |
| words | 0.22 s, 68 MB | 0.34 s, 90 MB | 0.54 s, 175 MB |
| graph_csr | 0.64 s, 109 MB | 1.06 s, 108 MB | 1.06 s, 174 MB |

The gaps: bintrees keeps its long tree on the heap (an inner `tape` frees
nothing); words and graph_csr size each array up front (one end to grow);
graph_csr's time is not memory: every `a[i]` is bounds-checked, which
Goose elides. C++ 0.97 s, Rust 1.18 s and Go 1.67 s on respond: README.md.

A tree pays in one `Tape::Tree` in document order (simdjson's layout):
4.6 MB JSON, 20 parses, 725 ms on the tape, 1081 ms as std/json's `Any`.
