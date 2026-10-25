# ris without a GC: the plan

Goal: a ris program links no collector. Every value is on a tape, in a
pool or static, as in [Goose](https://github.com/domify/goose) v2026.3
(spec §1.2: "no general-purpose heap"). The compiler itself is built by
Crystal and keeps its GC; only programs ris builds change. iyi keeps its
GC: `src/iyi/` code stays, unused by a ris build.

## What Goose does, and what ris takes
| Goose v2026.3 | ris today | ris target |
|---|---|---|
| Data stacks, scope frees §1.3 | Fiber tape, def frees | Same |
| Globals own a stack §11.1 | Program tape | Built (2a) |
| Roots, depth check §9.2 | Tape in tape places | Roots over defs |
| `reusable` pools §5.4 | Classes on the GC | `Pool(T)` |
| `T&<u32 in pool>` §3.9 | `Ary::Link` | Pool links |
| `root struct` (design) | `@[OnTape]`, regions | `@[Owner]` struct |
| Recursion holds no local §7.8 | Free | Scratch passed in |
| ADTs, no vtables §3.5 | Classes, unions | Unions, structs |
| No escaping closure §7.6 | Procs on the GC | Flat captures |
| Flat across threads §11.2 | No tape on channel | Same |
| `resource<U>` (design) | `@[Ffi]` pointers | Resource, `defer` |
Syntax stays Ruby's: def, blocks, modules, generics, unions, nil safety.
Goose's array zoo, packed layout and `recursive fn` mark are not needed.

## What goes, and its replacement (refusal names it)
* `class`, inheritance, `abstract`: `@[OnTape] struct`, unions, `case`.
* Object identity, aliasing graphs, `same?`: pool slots and links.
* `String`, `Array`, `Hash` on the heap: `Str`, `Ary`, `Tre`, tape `Map`.
* Escaping procs, `spawn` capturing state: flat captures, copied.
* Exception objects: error unions (SPEC III.1); `raise` is a panic.
* `WeakRef`, `GC`, `Box`, `reference_storage`: no replacement.
* Class variables, mutable constants: program tape or a global pool.

## Order (each step: gate green, docs, samples)
1. **Census and gate: built.** `ris heap [--user] FILE.ri` counts sites;
   `--no-gc` traps; `RIS_HEAP_STATS=1` counts calls; check.sh budgets both.
2. **Owners. 2a built:** program tape for constants and class variables,
   including top-level `@@`; fiber tape already built. Initializers run
   on `Program.tape` before user code; later stores require program data.
   `copy_to(Program.tape)` deeply copies Str, Ary, Tre and @[OnTape]
   fields. Growing state retains its owner; refill Ary with `clear`.
   Kernel-thread programs may only read roots after initialization; the
   compiler rejects later writes and program copies, through helpers too.
   Initializers cannot suspend; uncertain stores require an explicit copy.
   **2b pending:** @[Owner] structs, with a region per growing field,
   freed with the owner. The copy API already takes an owner parameter.
3. **Roots.** A tape value stored in a field or returned carries its
   owner; the store rule of Goose §9.2 checked across fields and defs,
   no annotations. Today's block checks become its special case.
4. **Pools.** `Pool(T)`: `alloc`, `free`, slots always valid; links
   `Pool::Link(T)` as `T&<u32 in pool>`. `SlicePool(T)` for runs (text
   buffers). Trees, graphs, sessions, caches move here.
5. **No classes in .ri.** Refuse `class`, naming `@[OnTape] struct`, a
   union or a pool. Procs: refuse non-flat captures. Recursion: refuse a
   growing local held across a recursive call; pass scratch in.
6. **std.** Module by module, bytes first: text, collections, JSON, URI,
   HTTP (mostly done), IO and sockets (buffers on the fiber tape), Log,
   Time, Regex and OpenSSL as resources. Errors as unions.
7. **Delete.** `String`, `Array`, `Hash` leave the ris prelude; the ris
   build drops the collector. `ris heap` must list nothing outside the
   runtime's own queues and fiber stacks.

## Risks
* Roots across defs is the hard part: Goose specializes per root.
  Start conservative, refuse when unsure; error text names the fix.
* Pool reuse reads a stale same-typed value (Goose §9.4): safe, but a
  logic bug class GC code lacks. A generation tag in debug builds.
* Merges from iyi conflict more each step; resolve at merge time.
* ris-bench's respond.ri must keep its checksum at every step.
