# Tape API

The tape surface of ris, one feature at a time, each with a runnable
example. Start with LEARN.md; come here for the details. Exact signatures
are in `src/iyi/tape.iyi`, the rules in TAPE_DESIGN.md.

## Open a tape

Use tape do … end around bounded work: a request, a parse or a batch. Allocation
requires an active tape; without one the program terminates. The block normally
returns nil. Nested tape blocks share the active tape; local_tape owns separate
storage.

```crystal
tape do
  text = Tape::String.new("hello")
  tape do                 # shares the active tape
    puts text
  end
  local_tape do           # separate storage, freed here
    puts text             # outer strings may be read
    temporary = Tape::Array(Int32).new
    temporary << 42
    puts temporary[0]
  end
end                       # owning tape is released
```

The owning scope releases storage on normal and early exits, including panic. In
local_tape, outer Tape::String values are readable, but other outer tape values,
mutable containers and tape self are unavailable. Inner values cannot be stored
into outer variables or containers. Prepare heap-owned inputs before entering
when needed.

## Borrow, copy and slice text

Tape::String is a byte view. as_tape borrows a String; Tape::String.new copies
it. Slices borrow their source rather than allocating another string. Byte
indexing is not Unicode character indexing: a UTF-8 character may occupy several
bytes.

```crystal
tape do
  source = "name=ris&count=42"
  text = source.as_tape          # borrow heap bytes; no copy
  owned = Tape::String.new(source) # copy bytes onto tape
  puts text[0, 4]               # name; borrowed slice
  puts text[5..7]               # ris; inclusive range
  puts text[0]                  # 110; UInt8, not Char
  puts text.bytesize            # 17; bytes, not characters
  puts text.index('=')          # 4; nil if absent
  puts text.starts_with?("name=")
  text.split('&').each { |part| puts part }
  puts "42".as_tape.to_i        # 42
  puts "oops".as_tape.to_i?     # nil
end
```

Read with bytesize, empty?, each_byte, each_line, index(char, offset),
includes?(char), starts_with?(prefix) and equality against tape or heap strings.
split(char) returns a Tape::Array(Tape::String) of views. Numeric readers
include to_i, to_i?, to_i64?, to_i64?(base) and to_f. Keep every view within its
source lifetime.

## Build output directly on tape

Tape::String.build(capacity) yields a writer and returns its finished text. <<
accepts strings, characters and supported values; append adds text, push adds a
byte, append_int and append_float format numbers. append_html_escaped handles
HTML text. Write the result directly with puts or io << text.

```crystal
tape do
  body = Tape::String.build(128) do |writer|
    writer << "Hello, " << "ris" << '!' << 42
    writer.append_html_escaped(" <tag>")
  end
  puts body                  # Hello, ris!42 &lt;tag&gt;

  # A writer can also remember where a piece of text landed.
  writer = Tape::String::Writer.new(64)
  writer.append("Hello, ")
  name = writer.append_span("ris") # the position of "ris"
  greeting = writer.finish
  puts greeting              # Hello, ris
  puts greeting[name]        # ris
end
```

A standalone Writer also offers length, reserve(total), truncate(length),
shift(count), clear and finish. append_span returns an offset and byte length
for later lookup. Treat finish as the handoff to readers: consume its views
before reusing or changing the writer. clear reuses storage; it does not make
old contents safe to retain.

## Collect and transform values

Tape::Array(T).new(capacity) creates an empty array. The block and fill-value
constructors create count elements. Arrays may contain tape strings and OnTape
structs, unlike ordinary heap arrays. Indexing is checked. Copies of the
container value share its storage; dup creates a separate element array, not
deep copies of nested data.

```crystal
tape do
  numbers = Tape::Array(Int32).new(8) # capacity, initially empty
  numbers << 3 << 1 << 2
  squares = Tape::Array(Int32).new(4) { |i| i * i }
  zeros = Tape::Array(Int32).new(4, 0)
  numbers[0] = 4
  numbers.sorted.each { |n| puts n } # 1, 2, 4
  puts numbers.select { |n| n > 1 }.sum # 6
  puts squares[3]                    # 9
  puts zeros.size                    # 4
  text = Tape::String.build do |writer|
    numbers.join(writer, ", ")
  end
  puts text                          # 4, 1, 2
end
```

Use size, empty?, push / <<, [], []=, pop / pop?, first / first?, last?, clear,
each and each_with_index. Transform with map, select, reject, reversed, dup, +
and concat; query with includes?, index, count, any?, all?, find, reduce, sum,
min_by and max_by. sorted / sorted_by return arrays; sort_in_place /
sort_in_place_by mutate the existing array. join writes into a tape writer.

## Give tape data a type

@[OnTape] allows a struct to contain tape values and subjects it to their
lifetime restrictions. It is a storage constraint, not a command that moves
ordinary String, Array or class allocations onto tape. Define to_heap explicitly
when a record needs an owned representation.

```crystal
@[OnTape]
struct Row
  getter name : Tape::String
  getter count : Int32

  def initialize(@name, @count)
  end

  def to_heap
    {name.to_heap, count}
  end
end

tape do
  rows = Tape::Array(Row).new
  rows << Row.new("ris".as_tape, 42)
  puts rows[0].name
  retained = rows.to_heap # heap Array of heap-owned tuples
  puts retained[0][0]
end
```

Tape values can be locals, function arguments and results within their owning
lifetime, OnTape fields and Tape::Array elements. They cannot be class fields,
plain struct fields, class variables, heap-container elements, captured proc
values or channel messages. Copying an OnTape struct does not copy the bytes it
references.

## Keep a result after the tape ends

Call to_heap while the source is alive. Tape::String becomes a heap String;
Tape::Array and IndexView become heap arrays, converting elements through their
own to_heap when available. A custom OnTape struct must define that conversion
itself. A helper may return a tape value to a caller whose tape remains active,
but cannot return storage owned by a tape it closes.

```crystal
def make_body : Tape::String
  Tape::String.build { |writer| writer << "Hello, ris" }
end

def retained_body : String
  tape do
    return make_body.to_heap
  end
  ""
end

puts retained_body # safe after the tape has been released
```

Implicit heap text conversions are restricted. to_s, interpolation into a heap
string and writes into String::Builder require an explicitly marked
@[TapeToHeap] function. Prefer the named to_heap boundary. puts text and io <<
text consume tape text directly; interpolated output can be written directly
without first building a heap string.

## Scan without allocating tokens

Tape::Scanner tracks a byte offset into a Tape::String and returns borrowed
views. scan consumes a matching prefix; check tests without consuming; skip
returns the consumed length. The until variants search through the delimiter and
include it. A failed match returns nil.

```crystal
# Split an HTTP request line into its parts. The scanner walks the text
# in place: every piece it returns is a view, nothing is copied.
tape do
  scanner = Tape::Scanner.new("GET /learn.html HTTP/1.1".as_tape)
  method = scanner.scan("GET")      # matches at the start, or nil
  scanner.skip(' ')                 # step over the space
  length = scanner.rest.index(' ') || 0
  path = scanner.scan(length)       # the next `length` bytes
  scanner.skip(' ')
  puts method                       # GET
  puts path                         # /learn.html
  puts scanner.rest                 # HTTP/1.1
  puts scanner.offset               # 16: bytes read so far
end
```

Use string, offset / offset=, eos?, rest, current_byte, peek(count),
advance(count = 1), reset and terminate to control traversal. scan, skip, check
and matches? accept tape or heap text, a Char or a byte count; scan_until,
skip_until and check_until accept text or a Char. These are literal byte
matches, not regular expressions.

## Validate indirect indexes once

values_at(indexes) validates every target index and returns Tape::IndexView(T).
It is an indirect read/write view, not a copied selection. Invalid target
indexes fail at construction; [] and []= access the corresponding target
elements. Use size, index(k), each and to_heap as needed.

```crystal
# Pick items by index without copying them. The view writes through.
tape do
  prices = Tape::Array(Int32).new(3) { |i| (i + 1) * 100 } # 100, 200, 300
  picks = Tape::Array(Int32).new
  picks << 2 << 0                  # the third and the first price
  cart = prices.values_at(picks)   # a view, not a copy
  puts cart[0]                     # 300
  cart[1] = 90                     # a discount: changes prices[0]
  puts prices[0]                   # 90
end
```

The compiler removes bounds checks when it proves them from each or a while i <
array.size loop. @[CheckFree] on a function requires its checked operations to
be proven safe; compilation fails if a check remains. It is a verification
request, not permission to access arbitrary memory.

## Use links and spans for flat records

Tape::Link(T, I) stores a typed element index rather than a pointer. Choose
UInt8, UInt16 or UInt32; the maximum value is reserved for none.
array.link(index, width) names an existing element; next_link(width) names the
next append position. Following a link checks it against the array; it does not
identify which array it belongs to.

```crystal
# A flat record holds no pointers: text is a Span (where it sits in one
# string) and a reference is a small index. The whole array is plain
# bytes, so it can be saved and loaded back as is.
@[Tape::Flat]
struct User
  getter name : Tape::Span               # position in the names string
  getter boss : Tape::Link(User, UInt16) # index of another User, or none

  def initialize(@name, @boss)
  end
end

tape do
  writer = Tape::String::Writer.new(32)
  ada = writer.append_span("Ada")
  bob = writer.append_span("Bob")
  names = writer.finish                 # "AdaBob": all names in one string

  users = Tape::Array(User).new
  users << User.new(ada, Tape::Link(User, UInt16).none) # 0: no boss
  users << User.new(bob, users.link(0, UInt16))         # 1: boss is Ada
  puts names[users[1].name]                             # Bob
  puts names[users[users[1].boss].name]                 # Ada

  loaded = Tape::Array(User).load(users.bytes)          # bytes in, records out
  puts names[loaded[loaded[1].boss].name]               # Ada
end
```

Tape::Span stores start and size, identifying bytes in a separate string via
text[span]. @[Tape::Flat] records contain only numbers, links, spans or other
flat records, without pointers. Tape::Array(T).bytes and .load(bytes) support
these flat representations. Keep the accompanying text for spans; raw record
bytes are not a portable, versioned file format or a substitute for validating
external data.

## Read and write binary fields

Tape::String.read_bytes_at(Type, offset) reads a little-endian integer at a byte
offset. Tape::String::Writer.write_bytes(value) appends one. Supported types are
signed and unsigned 16-, 32- and 64-bit integers; offsets need not be aligned
and out-of-range reads fail.

```crystal
import std/int

# A 6-byte binary header: a 4-byte id, then a 2-byte port.
tape do
  header = Tape::String.build do |writer|
    writer.write_bytes(42_u32)   # bytes 0..3
    writer.write_bytes(8080_u16) # bytes 4..5
  end
  puts header.bytesize                        # 6
  puts header.read_bytes_at(UInt32, 0).to_i32 # 42
  puts header.read_bytes_at(UInt16, 4).to_i32 # 8080

  # A byte array can also patch a field in place.
  buffer = Tape::Array(UInt8).new
  buffer.write_bytes(42_u32)
  buffer.write_bytes_at(0, 99_u32)            # overwrite the id
  puts buffer.read_bytes_at(UInt32, 0).to_i32 # 99
end
```

Tape::Array(UInt8) also supports write_bytes(value), read_bytes_at(Type, offset)
and write_bytes_at(offset, value). The last operation overwrites existing bytes
and requires the entire field to fit. These explicit little-endian operations
suit binary protocols; they differ from the raw flat-record representation
returned by an array's bytes method.

## Store a tree as one stream

Tape::Tree(T) stores entries in document order instead of allocating an array
for every node. open(value) starts a container, leaf(value) adds a child without
descendants and close(index) marks the end of a container. Build and close
nested containers before reading their subtrees.

```crystal
# A tree stored as one flat stream: open a node, add children, close it.
tape do
  tree = Tape::Tree(Int32).new
  root = tree.open(1)   # 1
  tree.leaf(2)          # ├─ 2
  sub = tree.open(3)    # └─ 3
  tree.leaf(4)          #    └─ 4
  tree.close(sub)
  tree.close(root)
  tree.each_child(root) { |child| puts tree[child] } # 2, 3: direct children
  puts tree.stop(sub)   # 4: the index right after 3's subtree, to skip it
end
```

open and leaf return Int32 indexes; [] reads a value and size counts all
entries. stop(index) returns the exclusive end of a subtree. each_child(index)
visits direct children and skips their descendants in one jump. Reading the end
of an unclosed container fails. This layout suits parsed documents and other
trees built once and traversed repeatedly.

## Lifetimes and performance

The tape belongs to the running fiber and follows it across switches. A spawned
fiber gets its own tape and cannot capture its parent's tape values. Used tape
words are scanned as GC roots, so tape records can refer to ordinary heap
objects without making those objects tape allocations.

Allocation bumps through mapped storage. Growing containers extend in place at
the end when possible; otherwise they move to a region of their own. The
compiler can reclaim a function, loop iteration or block's temporary storage
when it proves nothing survives it. Do not depend on reclamation across next or
assume every nested block frees its own region.

Use a capacity estimate for writers and arrays, reuse containers with clear only
after consuming their old contents, and send output directly to its destination.
Avoid tape → heap → tape round trips. Compare representative workloads with and
without tape; it helps most when many short-lived allocations share a lifetime.

Set RIS_TAPE_STATS=1 when running a program to report moves and mappings at
exit. Use local_tape when a temporary phase must release its storage before the
surrounding operation finishes. Bounds and lifetime checks remain part of the
programming model.

Raw-pointer escape hatches are not application APIs. @[TapeUnsafe] is restricted
to the standard library; application code must keep tape values within the
checked storage and lifetime rules.
