# Tape API

Every tape type, each with a short example. Start with LEARN.md; exact
signatures are in `src/iyi/tape.iyi`, the rules in TAPE_DESIGN.md.

## Tape, text, arrays, to_heap

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
  kept = line.to_heap                       # a String, kept after the tape
  puts kept                                 # id=7
end
```

Text is bytes: `text[0]` is a UInt8. Strings have `split`, `index`,
`starts_with?`, `to_i?`; arrays `map`, `select`, `each`, `join(writer)`.
`to_s` or interpolation to a heap String need `@[TapeToHeap]`; prefer
`to_heap`. A def may return tape data to a caller whose tape is still open.

## Records: @[OnTape]

```crystal
@[OnTape]
struct Row
  getter name : Str
  def initialize(@name); end
  def to_heap; name.to_heap; end
end

tape do
  rows = Ary(Row).new
  rows << Row.new("ris".as_tape)
  puts rows.to_heap[0]                      # ris
end
```

Tape values may be locals, arguments, results, @[OnTape] fields and
Ary elements; never class fields, heap containers, procs or channels.

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
to its IO. `RIS_TAPE_STATS=1` counts moves. `@[TapeUnsafe]` is std-only.
