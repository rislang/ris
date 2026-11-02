# Tape API

Every tape type, each with a short example. Start with LEARN.md; exact
signatures are in `src/iyi/tape.iyi`, the rules in SPEC.md.

## Tape, text, arrays, copy_to

`tape do … end` holds a request, a parse or a batch; the owning block frees
all at its end, early exits and panics included. A nested `tape` shares it;
every def, loop round and block inside frees its own temporaries when it
ends (SPEC 1.1). Main and each fiber have an implicit tape.

```crystal
tape do
  text = "name=ris"                         # a static view
  puts text[5, 3]                           # ris: a view, not a copy
  numbers = Array(Int32).new
  numbers << 3 << 1 << 2
  puts numbers.sorted.sum                   # 6
  line = "id=#{7}"                          # built on the tape
  kept = line.copy_to(Program.tape)         # kept after the tape
  puts kept                                 # id=7
end
```

Text is bytes: `text[0]` is a UInt8. Strings have `split`, `index`,
`starts_with?`, `to_i?`; arrays `map`, `select`, `each`, `join(writer)`.
Retain with `copy_to(owner)`; `to_heap` is a historical spelling of a copy
on the current tape. A def builds its result in its caller's scope (SPEC
1.5); a result that would have to be copied out is refused (SPEC 1.9).
A String's `to_unsafe` is refused, save as a `lib` fun's direct argument in
an `@[Ffi]` module.

## Records: @[OnTape]

```crystal
@[OnTape]
struct Row
  getter name : String
  def initialize(@name); end
end

tape do
  rows = Array(Row).new
  rows << Row.new("ris")
  kept = rows.copy_to(Program.tape)         # rows outlive the tape
  puts kept[0].name                         # ris
end
```

Tape values may be locals, arguments, results, @[OnTape] and class fields
and Array elements; each store must not outlive its source (SPEC 3.2). A
plain struct's field refuses them; between tasks a message is copied (5.2).

## Owners

A class with a growing field (`Array`, `RisTree`, a builder) is an owner
(SPEC 2.1). Each growing field has its own stable space and grows on its
own. Build it only with `x = T.new` at a named local or program
declaration, or with `copy_to(owner)`; instance and space end with that
declaration's scope.

```crystal
class Workspace
  getter rows = Array(Int32).new
  def add(n : Int32) : Nil
    @rows << n
  end
end

class Holder
  getter work : Workspace
  def initialize(@work : Workspace); end
end

def fill(work : Workspace) : Workspace
  work.add 1
  work                                      # a parameter's owner may return
end

workspace = Workspace.new
same = workspace                            # an alias, not a copy
fill(same)
holder = Holder.new(workspace)              # a field holds a reference
holder.work.add 2
list = [workspace]
puts list[0].rows.size                      # 2
kept = workspace.copy_to(Program.tape)      # a deep copy in fresh space
```

Every use but the construction is a reference, as for any class: `=`,
arguments, fields, Array elements and nilables alias it. No reference may
outlive the owner (SPEC 3.2), and a shrink is checked through every alias
(SPEC 3.3).

Refused, each with the safe form in its message:

* A temporary, argument, element or field initializer: `use(Workspace.new)`,
  `owners << Workspace.new`, `getter w = Workspace.new`. Declare it with a
  name and pass the variable.
* A second construction into one name: `a = Workspace.new` twice.
* Returning a def's own local owner, directly or through an alias: return
  a field view, take the owner as an argument, or `copy_to(owner)`.
* A subclass of an owner: use a field referencing a named owner.
* Sharing with another task (SPEC 5.1), and any byte image, raw copy or
  FFI layout (SPEC 2.3).

If `initialize` panics, built fields are reclaimed with the enclosing
scope, not rolled back at the call. Panics end the task; `rescue` is
refused, so no half-built binding is seen.
`test/ris/owner_construction_panic.ri` checks the bounded cleanup with
`RIS_TAPE_STATS=1`; `test/ris/refused/owner_*.ri` are the refusals. See
`doc/reference/iyi/source/SPEC.md` III.1.4 for the task panic rule.

## Scanner, links, binary fields, trees

```crystal
import std/int

tape do
  s = String::Scanner.new("GET /a HTTP/1.1")
  puts s.scan("GET")                        # GET; nil on no match
  s.skip(' ')
  puts s.scan_until(' ')                    # "/a ": through the space

  head = String.build { |w| w.write_bytes(8080_u16) }
  puts head.read_bytes_at(UInt16, 0).to_i32 # 8080: little-endian

  tree = RisTree(Int32).new
  root = tree.open(1)
  tree.leaf(2)
  tree.close(root)
  tree.each_child(root) { |c| puts tree[c] } # 2
end
```

`values_at(indexes)` gives a checked view that writes through. A
`@[Tape::Flat]` struct holds only numbers, `String::Span`s (`text[span]`) and
`Array::Link(T, UInt16)` indexes; `array.bytes` and `.load(bytes)` round-trip.

## SlicePool

`SlicePool(T)` keeps initialized typed runs in one growing backing array
on its owner's tape. Use fixed-size elements and keep `SlicePool::Run(T)`
views in collections instead of growing values. A nested container holds its
inner arrays as runs of a SlicePool it owns (SPEC 7.4); an owner in an
Array is a reference to a named owner (SPEC 2.1).

```crystal
tape do
  pool = SlicePool(Int32).new(128)
  row = pool.alloc_slice(4)
  row[0] = 42
  rows = Array(SlicePool::Run(Int32)).new
  rows << row
  row = pool.realloc_slice(row, 8)
  rows[0] = row
  pool.free_slice(rows[0])
end
```

`alloc_slice(n)` takes the first free span large enough, in offset order,
or extends the backing array, using a free tail first. New and reused
slots receive defaults: zero for numbers, false for Bool, the zero Char,
empty String, nil for nilable types, and `T.new` for other defaultable types.
`free_slice(run)` merges touching free spans without destroying values or
closing resources. Stale views still read valid typed values and see
subsequent replacements. Double free is a logic error, not a resource
cleanup operation.

A run provides `offset`, `size`, checked `[]` and `[]=`,
`run[start, count]`, `each`, `each_with_index` and `map`. The handle follows
the pool's backing storage across growth. `Run.new(array, offset, size)`
forms a checked view of an existing array; pool operations check its
membership before changing anything. Empty views free nothing and can
be reallocated by any pool. Sizes, bounds, overflow and foreign nonempty
runs fail with allocation-free fatal diagnostics.

`realloc_slice(run, n)` shrinks by freeing the suffix. Growth stays in
place at the tail, or consumes an adjacent free span (extending a free
tail when needed). Otherwise it frees the old run and allocates another,
preserving its typed prefix even when the spans overlap. Keep the returned
handle: existing handles retain their original offsets and lengths.
Reallocation refuses elements containing `Array::Link`; allocate and free
such runs without relocation. `run.copy_to(owner)` deeply copies the
viewed elements to the destination tape.

`SlicePool::List(T).new(pool : SlicePool(T?))` is a mutable row backed
by shared pool runs. It provides `size`, `empty?`, `[]`, `[]=`, `<<` and
`each`. Copies share one run handle; growth updates that handle for all
aliases. Multiple lists share the pool's backing reservation. Elements
must support run relocation. A list's `copy_to(owner)` copies its elements.

YAML tape values store sequence and mapping runs in a shared parser pool.
TOML uses pooled lists while building tables and fixed runs for arrays;
collections hold these views rather than nested growing arrays.

## Lifetimes and speed

Each fiber has its own tape; a spawned fiber cannot take its parent's values.
Size writers and arrays up front, refill with `clear`, write output straight
to its IO. `RIS_TAPE_STATS=1` counts side transfers and growth moves.
`@[TapeUnsafe]` is std-only.

## Numeric and log text

`writer << number` writes integer and floating text directly. The
prelude integers also have `number.to_s(writer, base = 10)` for bases
2..36, including signed minimum and unsigned maximum values. An invalid
base panics without heap allocation. `text.inspect(writer)` quotes bytes,
including malformed UTF-8, into the same builder. The String-returning
inspection and integer APIs are migration wrappers on these writers.

`std/log_text` has no clock or backend state. Its `LogField` records view
caller text; `LogText.write(source, severity, message, fields, writer)`
appends a log line after the timestamp the caller wrote, without a final
newline. `std/log` uses it for synchronous IO: messages borrow `String`,
metadata uses `Array(LogField)`, and the default formatter writes directly.
A retaining or custom legacy
backend copies a `TapeEntry` to a heap `Entry` at that boundary. Logger,
context and backend setup still allocate; their ownership is TODO 5b/9.

## HTTP heads and query serialization

`std/http_head` isolates parsing from transport and clock setup. Its
`HeadParser.parse_head(bytes, from, complete, fields)` (also
`Server.parse_head`) returns
`ParsedHead | HeadError | Nil`.
Head fields view the input; `HeadError.message` is a `String` diagnostic on
that same caller tape.
`Incoming.params` and `Params.parse(text : String)` return a `Query` with
decoded fields on the tape.

`Query.to_s(writer)` and legacy `Params.to_s(writer)` append form data to
the caller's builder, preserving duplicate keys and order. Parsing a
malformed query escape keeps the literal percent byte; serialization
escapes it. `URI.encode_www_form(text : String, writer)` writes each encoded
byte directly. Reserve up to three output bytes per input byte when
sizing a builder. `Params.to_s` is a String wrapper around the writer.

## URI references

`URI.parse(text : String)` returns an `@[OnTape] ParsedURI`. Its scheme,
host, path, query, fragment, user and password view the input bytes;
user and password preserve their written escapes. `URI.parse?` returns
nil for invalid references; `parse` panics with a tape diagnostic.
`parsed.to_s(writer)` appends a reference to the caller's builder.
`parsed.normalize` returns a record with lowercase scheme and host,
uppercase host escapes, no default port and no path dot segments.
Relative paths retain leading `..` segments until resolution.
`normalize_in_place` updates a mutable record. Retain the record with
`copy_to(owner)`.

`URI.encode`, `encode_path`, `encode_path_segment`, `encode_userinfo`
and `encode_www_form` take `String` and a caller builder. Allow three output
bytes per input byte. `URI.decode?(text : String, writer, plus_to_space)`
returns Bool, validating all escapes before appending any bytes; failure
leaves existing output intact. Without a writer it returns `String?`;
`decode` returns `String` or panics. Form decoding defaults to translating
`+` into a space.
URI resolution and IDNA host conversion remain legacy APIs.

## Published runtime limits
`RisRegion` starts tapes at 67,108,864 bytes (64 MiB),
not a cap. Each mapping adds a 64-byte header and rounds to 65,536 bytes.
Checked UInt64 arithmetic permits at most 2^64 - 65,536 mapped bytes;
the OS address space and available memory usually impose a smaller limit.
`String` byte lengths and `Array`/`RisTree` counts are at most 2^31 - 1.
Region and side-region lists have no fixed count cap; allocation failure
is fatal. Each growing value reserves its own side region at
construction, before publishing elements. The default reservation is
128 MiB (`SIDE_RESERVE`, backend policy), capped at (2^31 - 1) times the
element width; a larger initial capacity reserves exactly that capacity.
MAP_NORESERVE commits pages on touch; a final 64 KiB guard is inaccessible.
Growth never moves elements. Exceeding the reservation exits with an
allocation-free fatal error, before mutation and without fallback.
Stats count copying side transfers separately from growth moves; both
counts are zero. Construction reservations count as mappings.
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
`exit` runs the calling task's defers, innermost first, then flushes runtime
stdio and ends the process, as iyi III.1.4 specifies. Other tasks' defers
do not run. See [iyi](reference/iyi/source/SPEC.md).
