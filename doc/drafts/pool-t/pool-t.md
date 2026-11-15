# Pool(T): typed slots, replacement, checked handles (SPEC 6.1)

Status: revised after EGM review (consolidated_review_report.md). All
blockers B1-B4 and majors M1-M9 are answered below; Q1-Q6 take the
reviewers' joint recommendation, confirmed by the user on 2026-11-15.

## Problem

SPEC 6.1 is the last todo clause before ris 0.1.0. It promises
`Pool(T)` and `SlicePool(T)`; only `SlicePool(T)` exists
(src/ris/tape.ri:3500). There is no single-slot pool, no proof that a
stale view reads a typed replacement, and no generation-checked handle.
A program that needs one object per slot (tree nodes, sessions, timers)
today abuses `alloc_slice(1)`, paying a span search per allocation and
getting no stale-handle detection.

## What the clause promises

6.1 text: "typed slots/runs; free keeps values valid, stale views see
typed replacements; generations only guard checked handles."

Read with 6.2-6.6 and Goose §5.4 (`reusable`, goose_spec.md:1637):

* Typed slots: a pool holds elements of one type `T`; no raw bytes.
* Free keeps values valid: a freed slot stays an initialized `T` until
  the pool's tape ends. Freeing never runs cleanup (6.5).
* Stale views see typed replacements: an index or view to a freed,
  reused slot reads the new owner's `T`, never foreign memory.
* Generations only guard checked handles: a plain index is not checked
  against a generation; a `Pool::Handle(T)` is, and its use fails when
  stale. A handle cannot protect an escaped view.
* Kept from SlicePool: free keeps memory, slots never move (6.2);
  bounds and membership checked before mutation (6.3); `.load(bytes)`
  checks (6.4); classes refused as elements (6.5, new work, see
  Refusals); pool waste in RIS_TAPE_STATS (6.6).

## Decisions (Q1-Q6)

* Q1 c: the handle is `Pool::Handle(T)`, typed by its element, 8 bytes,
  modelled on `Array::Link`: flat, no pointer, `@[Tape::Flat]`. A
  handle used on another element type is a compile error. A handle of
  another pool of the same `T` is a typed replacement on purpose, like
  an index (M9).
* Q2 a: generations are always stored, one `UInt32` per slot.
* Q3 a: free by index bumps the generation too.
* Q4 a: no `push`/`<<`; they and `realloc` are defs whose body is a
  macro `raise` naming the safe form (B3).
* Q5: the name is `Pool(T)`, listed in UPSTREAM.md beside `SlicePool`
  as an exception to the Ris* rule for new types.
* Q6 a: handles ship in 0.1.0.

## API

```ruby
@[OnTape]
struct Pool(T)
  def initialize(capacity : Int32 | Int64 = 4)
  def self.next_gen(g : UInt32) : UInt32
  def size : Int32                      # slots ever made
  def alloc(value : T) : Int32          # last freed slot, else a new one
  def alloc_handle(value : T) : Handle(T)
  def free(i : Int32) : Nil             # slot stays a valid T
  def free(h : Handle(T)) : Nil
  def [](i : Int32) : T
  def []=(i : Int32, value : T) : T
  def [](h : Handle(T)) : T
  def []=(h : Handle(T), value : T) : T
  def get?(h : Handle(T)) : T?          # stale: nil
  def live?(h : Handle(T)) : Bool
end

@[Tape::Flat]
struct Pool::Handle(T)
  getter index : Int32
  getter generation : UInt32
end
```

* Layout: `@data : Array(T)` and `@gens : Array(UInt32)` in pool
  storage (`RisPoolStorage`, as SlicePool), and a freelist
  `@free : Array(Int32)`. Pool sits in src/ris/tape.ri beside
  SlicePool, as `RisPoolStorage` is private there (M6).
* Pool shares no private helper with SlicePool: its bounds check is an
  index check, not `Tape.storage`, and it needs no `default_value`
  (M6). Growth uses `Tape.storage` for the overflow check.
* `copy_to(owner)` copies the pool like any `@[OnTape]` struct;
  indices and handles stay valid in the copy, and the two diverge
  afterwards (M9).
* `Pool::Handle(T).new(i, g)` is public (B4): a handle can be forged
  anyway through `.load` or a zeroed value, so the guard is the check at
  use, not at construction.

## Generations (B1, M2, M3, M8)

* Parity: an odd generation means live, an even one free, 0 never
  live. `alloc` and `free` each step the slot's generation with
  `Pool.next_gen(g)`, a pure helper: `g + 1`, and a wrap from
  `0xFFFFFFFF` skips 0 to 2. The wrap point is 2^31 alloc/free cycles
  of one slot; it is documented, not checked.
* A handle is live when `0 <= index < size`, its generation is odd and
  equals the slot's. A zeroed handle is never live.
* `free(i)` on an even generation panics: a double free by index no
  longer hands one slot to two owners (M2).
* Indices are checked as `0 <= i < size`, so a negative index or a
  forged handle's negative index fails (M3).

## Refusals and the safe form each names

Compile time (each a `test/ris/refused/` fixture, matched on the whole
message by check.sh's `expect`):

* `Pool(File).new`, `SlicePool(E).new` where `E` holds a class through
  a union, tuple or struct field (B2), in code outside the runtime:
  "Pool(File) holds the class File; a pool holds values and its free
  never closes a resource: keep the File outside, store an index and
  close it explicitly (SPEC 6.5)". The check sits in `Call#instantiate`
  (call.cr) at the `new` call: the runtime's own Array keeps class
  elements' runs in a SlicePool, so a check on the type would refuse
  every `Array(SomeClass)`.
* `pool.push(v)`: "Pool has no push; use pool.alloc(value): it reuses
  freed slots".
* `pool << v`: "Pool has no <<; use pool.alloc(value): it reuses freed
  slots".
* `pool.realloc(...)`: "a Pool slot never moves (SPEC 6.2); use
  SlicePool(T) for runs".
* An element viewing another tape: as SlicePool, through the cross-tape
  escape checker (tape_escape_checker.cr), N3.

Runtime, each through `RisRegion.size_error`, exit code 1, before any
mutation (M8):

* Index out of range: "ris: Pool index out of bounds: N" (N may be
  negative).
* Double free: "ris: Pool slot already free: N".
* Stale, zeroed or forged handle in `free`/`[]`/`[]=`: "ris: stale Pool
  handle; check pool.live?(h) or use pool.get?(h): N".

## Compiler sites (M5)

* tape_checker.cr `growing_in` and tape_owner_checker.cr `growing?`:
  `Pool` is a growing value like `SlicePool`.
* tape_checker.cr `tape_in`: a `Pool::Handle(T)` holds no tape value;
  `T` only types it.
* tape_shrink_checker.cr `owner_argument?`: a `Pool(` argument is an
  owner a constructor may allocate through.
* call.cr `instantiate`: the 6.5 element check above.
* Not needed: `check_slice_relocation` (Pool has no relocation) and
  `check_tape_copy` (a Handle is a plain struct with number fields).

## Tests that prove it (M1)

Proofs are `test/ris/` files with `# spec: 6.1@VERSION` tags, run by
test/ris/check.sh, as for 6.2-6.6. AGENTS.md says runtime clauses are
proven this way.

1. `pool.ri` (plain run, prints `PASS: Pool`): alloc, read, write;
   free keeps the value; alloc reuses the freed index; the stale index
   reads the typed replacement (a String field); handles live and
   stale, `get?` nil, zero and negative handles stale, free by index
   stales a handle; `Pool.next_gen` at 0, 1 and the wrap; handles
   round-trip through `Array(Holder).load(bytes)` and a forged one fails
   at use; a copy keeps a handle live after the original frees it (M9).
2. `pool_errors.ri` (built once, one panic per mode, exit 1 and the
   exact line): bounds, negative read, negative free, double free,
   stale read, stale write (after free by index), stale free, zero
   handle, negative handle.
3. `pool_waste.ri` (RIS_TAPE_STATS=1): two freed Int64 slots read 16
   bytes of pool waste; after one reuse, 8 (M7: the global counter).
4. `refused/pool_push.ri`, `pool_shovel.ri`, `pool_realloc.ri`,
   `pool_file.ri`, `slice_pool_file.ri` (also 6.5 proofs, B2).

## Steps

1. Revise this draft (done); SPEC.md 6.1 text, CHANGELOG entry naming
   doc/drafts/pool-t/; UPSTREAM.md exception; AGENTS.md proof line.
2. Pool(T) and Pool::Handle(T) in src/ris/tape.ri; compiler sites.
3. Tests 1-4 in check.sh; triage.md citations (N3).
4. Drift report; `ris spec ack 6.1 6.5`.
