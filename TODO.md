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

## Workload blockers (goose-evaluations, 2026-10-26)

* jq under --no-gc runs 5-13x slower than Goose: find the cause once
  the ports run; speed tests otherwise stay off.

## Remaining tape semantics

* Stable growth on every supported tape target: replace moving backends
  outside Linux with address-space reservations and equivalent gates.
* Escaping closures outside program and joined task owners: pooled
  environments, including captured receivers; release them with their
  owner, check capture lifetimes and refuse unsupported escapes safely.
* Finish typed pool validation (TAPE_SPEC 6.1-6.4): audit remaining bounds,
  overflow, membership, stale views, reset lifetimes and external images.
  Borrowed Run constructors now retain Ary shrink lifetimes; gates cover
  constructor bounds and foreign Ary storage as well as pool storage.
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
* Define supported no-GC targets and gate each one; unsupported targets
  must fail explicitly rather than silently select a heap fallback.
* Audit final program binaries for collector linkage and forbidden heap
  allocator dependencies; keep the compiler's own GC choice separate.
* Make no-GC behavior the default after the semantic, runtime, workload
  and link gates pass; remove obsolete collector paths in ris programs.

## Later

* Finish ordinary class tape allocation for HTTP migration classes:
  migrate TlsStream connection/body holders. Opting these holders in
  reaches joined server captures and opaque streamed-body callbacks;
  establish checked lifetime contracts before enabling these paths.
  Unmarked runtime and std declarations still use the migration allocation
  ABI; selected std classes opt in with @[OnTape].
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

## Windows (on hold: not worked on now)

* Windows file metadata: move native wide-path conversion and auxiliary
  stat buffers onto tape, then gate Str metadata under --no-gc there.
  POSIX metadata and missing-file errors pass the zero-heap gate.
