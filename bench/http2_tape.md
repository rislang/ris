# HTTP/2 tape measurements

LLVM 23.1.3, Linux x86-64, `--release`, 2026-10-19. Reproduce with:

```sh
IYI=.build23/ris bash bench/http2_tape.sh
```

The default baseline reads HEAD's two modules with `git show`; it writes
nothing to `.git`. An optional argument names another baseline module
root containing `std/http.iyi` and `std/hpack.iyi`.

Each workload runs 20,000 times, baseline and tape interleaved seven
times. Time is the fastest run of each variant. Heap bytes are the
`IyiMark.allocated_since` delta with automatic collection off. Warm-up,
fixtures, and reporting are outside the interval. Matching checksums are
required. Numbers below are decimal MB; bytes vary by at most seven in
one workload because of allocator accounting.

| Workload | Heap MB before / after | Fastest ms before / after |
|---|---:|---:|
| HPACK encode, retained Bytes API | 3.934 / 1.114 | 10.936 / 7.125 |
| Huffman decode, retained String API | 2.229 / 0.721 | 9.865 / 6.558 |
| HPACK decode, consumed fields | 18.297 / 4.785 | 44.252 / 27.471 |
| Response fields and HPACK bytes | 10.646 / 0 | 18.567 / 8.774 |
| Buffered extension frames | 20.135 / 0 | 11.697 / 0.769 |
| Buffered request through response queue | 38.421 / 24.325 | 65.408 / 54.611 |

Response and decode workloads consume the same logical output within its
lifetime. The retained API workloads produce the same owned results.
Native decoding includes heap copies needed for dynamic-table entries.
The full request workload uses the existing String Request/Response API.

The frame and full request harnesses expose private connection state in
scratch copies of the modules. They preload identical wire bytes and
inspect/drain queued output without calling a socket. Draining restores
the simulated peer's connection window. These are CPU/allocation
measurements, not network throughput or interoperability tests.

## Ownership

The server opens one tape around the next request, handler and answer.
Nested library scopes share it. Frame payloads view the connection read
buffer until dispatch finishes. HPACK literals, Huffman output, decoded
field slots, response field slots, normalized names, numeric values and
encoded header bytes use that tape. Fixed slots avoid alternating growth.
Connection queues and HPACK tables retain heap data. Decoded fields copy
out only when queued; indexed/table-owned strings are reused. Encoded
frame slices copy out when the connection queues them for later flushing.
The String API's request, response and body remain retainable heap values.

## Dropped

An eager tape-decoder wrapper copied indexed strings back to the heap.
It used 13.569 MB versus 12.587 MB for the buffer-only implementation,
and fastest time was 33.877 versus 30.878 ms. The existing retained
Decoder path remains direct, sharing parsing logic with the tape path.

## Validation

LLVM 23 compiler build passed. The complete HPACK exercise, including its
mutation proofs, passed. Tape HPACK checks passed, including table reuse
across freed scopes and byte-identical native encoding. Buffered request
and response checks passed. Socket-based HTTP/2, HTTP interoperability,
and the tape socket/answer tests cannot pass in this sandbox: socket
creation fails with `Operation not permitted`. They require a rerun in
an environment that permits local sockets.
Non-socket HTTP checks pass in debug and release; the HTTP/2 exercise
builds in both modes. The tape gate passes 29 refusal checks and 29 run
checks; only socket_pair and answer fail at socket creation. The full
HTTP shell gate aborts after its peers cannot create listening sockets.
