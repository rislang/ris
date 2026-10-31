# Std tape port checkpoints

Uncommitted work. Gates run on minitest in ~/work/rispure-nogc.
Counts are the number of lines beginning FAILED in check.sh's output.
Each module's typecheck and focused gate run before the next module.
The inherited starting count was 79.

| Module | Status | Failures | Gate / remaining issue |
|---|---|---:|---|
| socket | blocked | 74 | DNS SvcbRecord needs compiler SPEC 7.4 |
| io | done | 73 | std_io_tape and pipe_wait; zero heap |
| http_head | done | 72 | http_head_tape; zero heap |
| http | partly | 72 | TLS reaches std/big's old String class extension |
| hpack | done | 70 | Round-trip, malformed input and pooled churn; zero heap |

Socket has tape errors and inputs, checked task handoff support, and
shared tape collection literal lowering. It still needs its resolver
and native scratch buffers ported after the nested-container blocker.

IO uses tape Arrays and builders. ByteFormat accepts String input and
writes into a caller's builder or IO. The focused gate checks Memory,
Sized, Delimited, MultiWriter, Hexdump and both byte orders. The pipe gate
also checks writer suspension and a closed reader.

HTTP head parsing uses an independent query module; URI re-exports its
Query and QueryPair names. Joined fields build on the caller's tape.

Changes in indexable, iterator, random and text are prerequisite fixes,
not completed ports of those modules. No heap or allocator fallback was
introduced to bypass a compiler refusal.

HPACK uses connection-owned SlicePool byte runs and fixed-size entry
handles. Eviction returns runs and refills the existing entry array.
Decoder output that must survive later eviction uses explicit copy_to.
The gate keeps a copied field across 1,000 updates, checks bounded byte
slots, and checks clear. HeaderField and TapeHeaderField name one tape type.
