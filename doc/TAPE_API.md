# Tape API

Every tape type, each with a short example. Start with LEARN.md; exact
signatures are in `src/iyi/tape.iyi`, the rules in TAPE_SPEC.md.

## Tape, text, arrays, copy_to

`tape do … end` holds a request, a parse or a batch; the owning block frees
all at its end, early exits and panics included. A nested `tape` shares it;
`local_tape` has its own storage. Allocating with no tape open ends the run.

```crystal
tape do
  text = "name=ris".as_tape                 # borrows; Str.new copies
  puts text[5, 3]                           # ris: a view, not a copy
  numbers = Ary(Int32).new
  numbers << 3 << 1 << 2
  puts numbers.sorted.sum                   # 6
  line = Str.build { |w| w << "id=" << 7 }
  kept = line.copy_to(Program.tape)         # kept after the tape
  puts kept                                 # id=7
end
```

Text is bytes: `text[0]` is a UInt8. Strings have `split`, `index`,
`starts_with?`, `to_i?`; arrays `map`, `select`, `each`, `join(writer)`.
Retain with `copy_to(owner)`; `to_heap`, `to_s` and `@[TapeToHeap]` are
migration heap sites. A def may return tape data to an open caller tape.

## Records: @[OnTape]

```crystal
@[OnTape]
struct Row
  getter name : Str
  def initialize(@name); end
end

tape do
  rows = Ary(Row).new
  rows << Row.new("ris".as_tape)
  kept = rows.copy_to(Program.tape)         # rows outlive the tape
  puts kept[0].name                         # ris
end
```

Tape values may be locals, arguments, results, @[OnTape] fields and
Ary elements; never class fields, heap containers, procs or channels.

## Named owners: @[Owner]

An `@[Owner]` struct can hold several growing `Ary`, `Str::Builder` or
`Tre` fields. Bind construction directly to a named local or program
declaration: `workspace = Workspace.new`. Grow each field independently.
Declare one owner per scope; pass its variable to helpers to borrow it.

Owners cannot be copied, reassigned, nested in fields or containers,
combined into tuples or unions (including nilable types), or returned
from a def as a local value. `@[OnTape]` records keep their existing rules.
Ordinary def arguments borrow the owner's storage, so field growth in a
helper updates the caller, including through nested calls. Owner methods
also mutate the receiver in place. Pass owners directly to defs; primitive,
Proc and foreign calls cannot take owner arguments.

In-place construction and returned borrows remain planned, as does stable
growth on first transfer.

## Scanner, links, binary fields, trees

```crystal
import std/int

tape do
  s = Str::Scanner.new("GET /a HTTP/1.1".as_tape)
  puts s.scan("GET")                        # GET; nil on no match
  s.skip(' ')
  puts s.scan_until(' ')                    # "/a ": through the space

  head = Str.build { |w| w.write_bytes(8080_u16) }
  puts head.read_bytes_at(UInt16, 0).to_i32 # 8080: little-endian

  tree = Tre(Int32).new
  root = tree.open(1)
  tree.leaf(2)
  tree.close(root)
  tree.each_child(root) { |c| puts tree[c] } # 2
end
```

`values_at(indexes)` gives a checked view that writes through. A
`@[Tape::Flat]` struct holds only numbers, `Str::Span`s (`text[span]`) and
`Ary::Link(T, UInt16)` indexes; `array.bytes` and `.load(bytes)` round-trip.

## Lifetimes and speed

Each fiber has its own tape; a spawned fiber cannot take its parent's values.
Size writers and arrays up front, refill with `clear`, write output straight
to its IO. `RIS_TAPE_STATS=1` counts side transfers and growth moves.
`@[TapeUnsafe]` is std-only.

## Published runtime limits
`IyiRegion` starts tapes at 67,108,864 bytes (64 MiB),
not a cap. Each mapping adds a 64-byte header and rounds to 65,536 bytes.
Checked UInt64 arithmetic permits at most 2^64 - 65,536 mapped bytes;
the OS address space and available memory usually impose a smaller limit.
`Str` byte lengths and `Ary`/`Tre` counts are at most 2^31 - 1.
Region and side-region lists have no fixed count cap; allocation failure
is fatal. On Linux a displaced value transfers once to a side region.
It reserves up to 1 GiB (`SIDE_RESERVE`, backend policy), capped at
(2^31 - 1) times the element width. MAP_NORESERVE commits pages on touch;
a final 64 KiB guard is inaccessible. Growth there never moves, and
exhaustion exits with an allocation-free fatal error, without fallback.
Other targets retain moving side mappings pending reservation support.
Stats count side regions and transfer bytes separately from growth moves.
The reservation follows
[Goose §1.2–1.3 and §10.4](reference/goose/docs/goose_spec.md).
Each worker caches at most 64 released initial-size tape mappings and
64 reserved side mappings, retaining at most 1 MiB warm in each.
Each group permits at most 2^31 - 1 live tasks (`IyiGroup::MAX_LIVE`).
There is no global task cap; metadata and stacks consume memory.
`IyiFiber::STACK_BYTES` is 262,144 bytes, plus a 4,096-byte guard page.
Main's stack limit is set by the OS; recursion has no fixed cap.
POSIX fault handlers use a 65,536-byte alternate stack. Exhaustion is fatal.
`RIS_TAPE_STATS=1` prints these limits from the runtime constants.
`exit` skips user cleanup and flushes runtime stdio. This differs from
`doc/reference/iyi/source/SPEC.md` III.1.4 and its exit rule near line 2382.
