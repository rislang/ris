# ris TODO

Rules: TAPE_SPEC.md. Work in this dependency order; each gate runs in
check.sh. Delete finished work in the same commit; keep check.sh green.

2. [L] Failure semantics before heap-backed runtime paths go.
   Publish limits (64 MiB is a start size, not a cap).
   Ensure LIFO on current locals; raise in cleanup is fatal; exit skips
   user cleanup (concurrency.iyi:3690 walks defers); signals set flags.
   Gate: panic, cleanup and exit subprocess tests.
3. [L] Named lexical/program owners; refuse copies, moves, temporaries,
   nesting and raw owner operations. Stable growth: growth now moves a
   value once (region.iyi:191); give each growing value reserved space
   (Goose) or change the spec with a changelog entry. Destination
   construction and partial-construction rollback.
   Gate: refusal cases, stable addresses, bounded rollback.
4. [L] Roots and effects: owner/path roots, joins, loop fixed points,
   read-back candidates, holders, operands; specialized call effects;
   contracts for opaque calls and iyimod; live-view shrink, suspension;
   recursion per Goose §7.8 (tape_lifetime_checker.cr:96 skips it).
   Gate: alias, dispatch, callback, loop and recursion cases.
5. [M] Pending results outside callee scratch and rollback. copy_to
   refuses classes (Object returns self, tape.iyi:1976), pointers and
   self-relative links; stays alias-free. Replace to_heap advice in
   tape_escape_checker, tape_lifetime_checker:119, tape_pointer_checker:317
   and bindings.cr:156 with copy_to(owner) or the caller's builder.
   Gate: results survive rollback; refused copies; bounded scratch.
5b. [M] std text and parsers onto the tape with existing tape types.
   Gate: each migrated module has zero heap on success and error paths.
6. [L] Pool/SlicePool: typed reuse, checked handles, size, membership,
   initialization, link and byte-image validation, reset, explicit
   relocation; pool free never closes a resource.
   Gate: stale views stay typed; invalid operations mutate nothing.
7. [L] Tasks, queues, wait nodes and escaping captures in pools; copy
   messages, results and panics to the receiver; bounded queues; failed
   receive keeps the message; owner isolation, TLS, ordered
   nonsuspending init and frozen sharing.
   Gate: full, closed, cancel, outliving-spawner cases with zero heap.
8. [M] FFI borrow/retain/cleanup, foreign-thread attach, unwind barriers.
   Gate: escape refusals, callback attachment, cleanup tests.
9. [L] Unboxed unions and dispatch; refuse heap classes; the rest of std
   by module: collections, IO, errors, resources.
   Gate: each module zero heap; refusals name the safe form.
10. [M] Every sample, branch and server request workload at zero heap;
   replace GC comparisons; keep checksums and the ris-bench respond copy.
11. [M] No GC by default; remove the ris allocator fallback, exemptions
   and collector linkage (gc_none still allocates: prelude.iyi:7572).
   Gate: link/symbol audit plus runtime allocation trap.

Alongside: RIS_TAPE_STATS gains owner paths, regions, committed peaks,
pool waste, copies apart from growth moves. Old root doc refs in bench/
(GC_DESIGN.md, AI_FIRST.md) point to doc/archive/iyi/ when touched.
