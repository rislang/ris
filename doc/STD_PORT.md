# Porting std to tape-only ris

[TAPE_TYPES.md](TAPE_TYPES.md) and SPEC section 7 define the model.
String, Array, Hash and RisTree are tape values. A string literal is a String
view of static bytes. There is no heap String, general heap, GC, fallback
or transition type. Unchanged language rules are in doc/reference/iyi/.

## Library API

Take String directly. Slice with [start, count] or byte_slice to answer a
view. split answers an Array of views. Never copy text just to accept it.
Write formatting and streaming results into the caller's String::Builder.
String.build and collection transforms use the caller's tape. A nested
tape block shares that tape. Every def, loop round and block frees its own
temporaries (SPEC 1.1), so a library needs no separate scratch.
A view stays valid only while its source owner lives.

Use clear to refill growing fields. Reserve capacity from input sizes.
Do not replace an Array field on every call: old storage remains until its
owner ends. No API exposes raw pointers. Runtime/FFI internals obtain the
pointer only at the OS call, with the required local safety mark.

## Retained state

copy_to(owner) deeply copies String, Array and tape structs into an
explicit owner, such as Program.tape. to_s, dup and the historical to_heap
spelling copy onto the current tape; none retains bytes beyond that tape.
Never retain a request's borrowed bytes in state.

Ruby syntax stays: String << and bang methods rebind the receiver; old
views keep their bytes. Nested containers use pool-run handles. Long-lived
containers own pools: stores copy into their runs, and overwrite, delete
and clear return runs for reuse. Other escaping stores must fail and name
copy_to(owner). Program.tape holds only data kept until program exit.

For independently replaced state, use typed Pool/SlicePool storage and
checked handles or run offsets. Free returns typed slots for reuse; it
does not collect memory. See the Goose design in
[owning_dynamic_data.md](reference/goose/docs/design/owning_dynamic_data.md).

RisByteCache in src/iyi/byte_cache.iyi demonstrates one reusable byte run.
Construct one named owner for a server or session. Borrow it in handlers;
store copies request bytes into SlicePool(UInt8), write_to writes into
the caller's builder, and clear returns the run for reuse. The example in
test/ris/std_foundations.ri keeps the owner in program storage and checks
replacement, reuse and reads after a handler returns. Extend this pattern
with typed entry slots and run offsets for an HPACK table or multi-key cache.

## Errors

Error#message answers String. A dynamic std error is an @[OnTape] struct
with String fields and an impl Error whose message returns a view or builds
on the caller's tape. Return the error through the normal result path.
To keep it beyond its source scope, copy the whole error with copy_to(owner).
The foundations test checks a formatted error and an explicit retained copy.
Static messages can simply return a literal. Do not add a heap exception
message, a hidden global owner, or an allocator fallback.

The automatic nested-container and long-lived-container placement in
TAPE_TYPES section 10 still needs compiler work. A refusal of that syntax
is a compiler TODO; do not evade it with a heap type, allocator fallback,
or a different public library API. The explicit owner example above is a
foundation for that placement, not its automatic implementation.
