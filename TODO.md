# ris TODO

Rules: TAPE_SPEC.md. Goal: no GC or general heap, including the runtime.
Measure: test/ris/heap_budget.txt, semantic gates and binary link audits.

How to work (fewer tokens, faster to the goal):

* Demand first: take the largest heap site in an existing workload.
  For an uncovered language guarantee, add a small representative gate.
  Move storage to tape or typed pools; lower changed budget rows in the
  same commit. Unrelated module migrations wait.
* One change, one relevant gate: check the promised behavior, including
  error paths the census cannot see. Zero counted allocations alone do
  not prove runtime exemptions or repeated use are heap-free.
* Replace, don't wrap: when a String API has a tape twin, grep the repo
  for callers. Few: move them to the tape API and delete the String API
  in one commit. Many: keep the wrapper for now.
* TODO holds open work only, one item per task; completed work lives in
  git log. Remove an item when its guarantee passes its gate, not merely
  when a sample's budget reaches zero.

## Remaining tape semantics

* Ordinary class `new` on the active tape; check reference lifetimes and
  refuse finalize. Existing copy_to must also handle these instances.
* SlicePool(T) minimum: typed runs, alloc/free/realloc, checked bounds
  and membership (TAPE_SPEC 6.1-6.3, Goose §5.4); the safe form 2.2 names.
* Refuse runtime-sized collections of growing values (Ary of Ary/Builder,
  growing fields in Ary elements), naming SlicePool (TAPE_SPEC 2.2). This
  bounds how many growing values live at once, which reservations need.
* Stable growth from the first published element, after the two above:
  remove the copying transfer in IyiRegion.tape_resize; each growing value
  reserves its own address space (TAPE_SPEC 2.2; Goose §1.2, §10.3-10.4).
  A first try reserving 1 GiB per value at construction failed: query's
  mapping and copy_deep's 100,000 nested arrays. Test views held before
  first growth, zero transfers, bounded mappings in serve and respond.
* Stable growth on every supported tape target: replace moving backends
  outside Linux with address-space reservations and equivalent gates.
* Escaping closures outside program and joined task owners: pooled
  environments, including captured receivers; release them with their
  owner, check capture lifetimes and refuse unsupported escapes safely.
* Validate typed pools as they enter use: bounds, overflow, membership,
  stale views and reset lifetimes (TAPE_SPEC 6.1-6.4).
* Concurrency storage (TAPE_SPEC 5.2): task records, wait nodes and
  queues in runtime typed pools; a buffered queue is bounded and send
  reports full; a failed receive keeps the message.
* Tape messages on channels (TAPE_SPEC 5.2): the queue owns a
  queued tape value, receive copies it to the receiver, close releases.
* For FFI paths in use, enforce borrow lifetimes, retained-storage owners,
  foreign-thread attachment and no unwind across foreign frames.

## Remove the heap and switch off the GC

* Audit runtime allocations hidden by RisHeap.runtime_depth; migrate the
  remaining sites, then remove counting and --no-gc enforcement exemptions.
* Remove general allocator fallbacks from ris programs. Distinguish
  gc_none's allocator behavior from ris_no_gc's allocation trap; audit
  remaining std and runtime paths required by supported workloads.
* Gate repeated server use under --no-gc beyond the full serve loop
  (passes): task cleanup and reused storage across groups.
* Define supported no-GC targets and gate each one; unsupported targets
  must fail explicitly rather than silently select a heap fallback.
* Audit final program binaries for collector linkage and forbidden heap
  allocator dependencies; keep the compiler's own GC choice separate.
* Make no-GC behavior the default after the semantic, runtime, workload
  and link gates pass; remove obsolete collector paths in ris programs.

## Later

* Complete the Pool/SlicePool surface beyond the validated paths in use.
* Sweep remaining std modules (collections, IO, errors); heap paths that
  block the default no-GC switch belong in the section above.
* Add 128-bit formatting, IDNA and URI resolution.
* Extend RIS_TAPE_STATS with owner paths and pool waste.

## Known failure to recheck

* Reproduce spec/compiler/iyimod_spec.cr's "carries the constants a
  module's own code reads": runtime constants appear in the constant
  list. Determine whether the artifact or the expectation is wrong;
  make tape-independent fixes in iyi first, or record them in UPSTREAM.md.
