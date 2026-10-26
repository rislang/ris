# ris TODO

Rules: TAPE_SPEC.md. Work in this dependency order; each gate runs in
check.sh. Delete finished work in the same commit; keep check.sh green.

3. [L] First transfer: growth still transfers a displaced value once
   into its reserved side region, moving published elements
   (region.iyi tape_resize). Start growing
   values in their own region, or refuse views across the first growth.
   Non-Linux targets still move. Refuse raw owner operations.
   Gate: no transfer of a viewed value.
5. [M] Remaining: allocate class copies on the owner (with step 9).
   Gate: destination ownership.
5b. [M] std text and parsers onto the tape with existing tape types.
   Gate: each migrated module has zero heap on success and error paths.
6. [L] Pool/SlicePool: typed reuse, checked handles, size, membership,
   initialization, link and byte-image validation, reset, explicit
   relocation; pool free never closes a resource.
   Gate: stale views stay typed; invalid operations mutate nothing.
7. [L] Keep iyi's runtime (src/iyi/concurrency.iyi): groups, Channel,
   select, cancellation, Share, III.5 init order, defer. ris adds: task
   records, wait nodes, escaping captures and defer closures
   (codegen.cr ProcLiteral mallocs a wrapper) in pools; copy messages,
   results and panics to the receiver; a buffered queue is bounded and
   reports full; failed receive keeps the message; owners per task, TLS
   without fiber borrows, nonsuspending init, frozen sharing.
   Gate: full, closed, cancel and group-exit cases with zero heap.
8. [M] FFI borrow/retain/cleanup, foreign-thread attach, unwind barriers.
   Start from iyi: a panic walks the defer registry, not frames (III.1.4);
   check what it does to foreign frames before adding a barrier.
   Gate: escape refusals, callback attachment, cleanup tests.
9. [L] Classes on the tape: new allocates on the active tape, roots
   track references, finalize refused. Unboxed unions and dispatch; the
   rest of std by module: collections, IO, errors, resources.
   Gate: class instances and each module zero heap; refusals name the
   safe form.
10. [M] Every sample, branch and server request workload at zero heap;
   replace GC comparisons; keep checksums and the ris-bench respond copy.
11. [M] No GC by default; remove the ris allocator fallback, exemptions
   and collector linkage (gc_none still allocates: prelude.iyi:7572).
   Use iyi's heap census and gc_none trap (UPSTREAM.md), not a new one.
   Gate: link/symbol audit plus runtime allocation trap.

Alongside: RIS_TAPE_STATS gains owner paths, regions, committed peaks,
pool waste, copies apart from growth moves. Old root doc refs in bench/
(GC_DESIGN.md, AI_FIRST.md) point to doc/archive/iyi/ when touched.
Known: spec/compiler/iyimod_spec.cr "carries the constants a module's own
code reads" fails before and after 4f: runtime constants (STDOUT, ...)
appear in the module's constant list.
