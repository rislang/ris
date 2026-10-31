# String, Array, Hash and RisTree: the final design

ris has no heap and no GC. Its data types are Goose's (cited as Goose and a
section of doc/reference/goose/docs/goose_spec.md, or stdlib.md), spelled
with Ruby's and Crystal's names. There is no second, heap-backed type of
any of them, no fallback allocator and no transition layer.

## 1. Where memory lives

Goose §1.2: there is no general-purpose heap and no malloc.

| Place | Holds | Ends |
|---|---|---|
| Static data | literals, constants | never |
| A tape (Goose's data stack) | what a scope builds | when its block ends |
| `Program.tape` | what lives as long as the program | at exit |
| `Pool`, `SlicePool` | state that outlives a request | at `free` |

A value that must outlive its tape is copied to a longer-lived owner with
`copy_to(owner)`: `Program.tape`, a pool, or the caller's tape. Nothing is
kept by accident: a value with no owner ends with its block.

## 2. String

Goose §3.7 has no string type: text is a `u8` array or a slice of one.
ris names the forms:

| ris | Goose | What it is |
|---|---|---|
| `String` | `const u8[:]` | a read-only view: pointer and byte count |
| a literal `"abc"` | static `const u8[:]` | a view of static bytes |
| `String::Builder` | `u8[>..]` | text being built, tops its tape |

* A `String` never owns or changes its bytes. Slicing (`s[i, n]`,
  `s[a..b]`), `split`, `strip`, `lines`, `chomp` answer views into the same
  bytes: nothing is copied (Goose stdlib `split`, `trim`).
* What builds new text builds it on the current tape: `+`, `*`,
  interpolation, `upcase`, `gsub`, `to_s`, `join`, `String.build`. The
  result is a `String` viewing the built bytes.
* Text output is Goose's `print`/`format`/`str` (§3.7): `puts`, `print`
  and `Builder#<<` write any value's text form in place; `to_s(builder)`
  is a type's own form, `inspect` the quoted one. No call makes a
  temporary string to print it.
* Bytes, not characters: `bytesize`, `[]` reads a byte, `each_char`
  decodes UTF-8 (malformed bytes are U+FFFD). UTF-8 is a convention.
* `==`, `<=>` and `hash` compare and hash the bytes, so a `String` is a
  `Hash` key as it is.

## 3. Array(T)

Goose §3.3 and §5. One growable array type, Goose's grow-only resizable
`T[>..]`, on its tape:

* `[1, 2, 3]`, `[] of T`, `Array(T).new(n)`. It reserves its own address
  space, so growth is a bump and never moves (Goose §1.3): a view taken
  before growth stays valid.
* Elements are fixed-size: numbers, structs, `String` views, links. An
  `Array(Array(T))` is written as in Ruby; its inner arrays are runs of a
  `SlicePool(T)` it owns, so every element stays fixed-size and indexes in
  O(1) (section 10; Goose §3.3 would make it sequential).
* Indexing is bounds-checked; a loop over `size` checks once.
* Shrinking (`pop`, `clear`, `truncate`) is allowed where no view into the
  array is live (Goose §5.1); the compiler proves it or refuses.
* A field refills with `clear`, never a new array per call.
* Views: `a[i, n]` and `a[a..b]` are `Array::View(T)`, Goose's `T[:]`.
* The Enumerable surface answers tape arrays: `map`, `select`, `reject`,
  `sort`, `sort_by`, `uniq`, `reverse`, `each_slice`, `flat_map`, `sum`,
  `min`, `max`, `tally`, `find`, `reduce`.

## 4. Hash(K, V)

Goose stdlib `dictionary`: open addressing, linear probing, power-of-two
capacity, in place on its tape.

* `{"a" => 1}`, `{} of K => V`, `Hash(K, V).new(n)`.
* Keys and values are fixed-size; a `String` key is a view of text the
  caller keeps (Goose: keys as `u8[:]` slices).
* ris keeps Ruby's insertion order, where Goose's order is unspecified:
  entries are kept in insertion order, and the slot table holds their
  indices (Ruby's st_table). Deletion marks the entry; iteration skips it.
* Each slot keeps hash bits as a tag, so a lookup compares keys only where
  tags agree, and growth does not rehash keys (Goose dictionary).
* It doubles in place at 2/3 load; `Hash.new(n)` sizes it for `n` entries.
* The surface: `[]`, `[]=`, `[]?`, `fetch`, `has_key?`, `delete`, `each`,
  `keys`, `values`, `map`, `select`, `reject`, `transform_values`, `to_a`,
  `size`, `clear`. A set is `Hash(K, Bool)`.

## 5. RisTree(T)

A tree in one array: nodes are `Array` elements, links are `Int32` indices
(Goose §3.9, relative references; Appendix A.2). No pointers, so a tree
copies as bytes and crosses tasks on the board.

* Children and siblings are indices; a JSON or HTML document is a `RisTree`
  of nodes whose text fields view the input (Goose stdlib json: keys and
  strings are slices of the text, escaped ones of a decoded buffer).
* A tree that outlives a request lives in a `Pool` or on `Program.tape`.

## 6. State that outlives a request

Goose §5.4, `reusable` arrays:

* `Pool(T)`: fixed-size slots. `alloc` answers an index, `free(i)` gives
  the slot back. A freed slot stays a valid value of its type, so a stale
  index reads another value, never freed memory.
* `SlicePool(T)`: runs of elements in one growing array (`alloc_slice`,
  `realloc_slice`, `free_slice`); free spans merge. Variable-length text
  that lives long (a TLS session, a cache entry, a header table) is a run
  of a `SlicePool(UInt8)`.
* A pool is owned by a program value or a task, never shared mutably
  across tasks (SPEC 5.1).
* Examples: an HPACK table is a `Pool` of entries and a `SlicePool(UInt8)`
  of their bytes; an autocert cache is a `Hash` from name to a pool index.

## 7. Across tasks

Goose §11.2: only flat values cross. A task's result and a `RisBoard`
message are copied: a `String`, `Array`, `Hash` or `RisTree` is packed and
rebuilt on the receiver's tape. A task may read what its spawner made
before the group started; it cannot keep a view of it past the group.

## 8. Rules for std and the runtime

* Take `String` input, write into the caller's `String::Builder`, answer
  views or `@[OnTape]` structs that view the input.
* Temporaries go on the caller's tape; a nested `tape` block shares it.
* Long-lived state goes in a `Pool`/`SlicePool` with an explicit owner, or
  on `Program.tape` for the program's life.
* `Error#message` is a `String`: a literal, or text built on the tape of
  the code that reads the error.
* Forbidden: a heap type, `malloc`, a bump allocator, a type
  that keeps a pointer into a tape it does not own.

## 9. What ris does not take from Goose

* Syntax: ris keeps Crystal's (`[1, 2]`, `{k => v}`, blocks, `puts`).
* Hash order: insertion order, as Ruby.
* Variable-size array elements (Goose's sequential `T[]`): ris uses
  `SlicePool` runs instead, so every `Array` indexes in O(1).
* Fixed and limited arrays (`T[k]`, `T[..k]`): `StaticArray(T, N)` for the
  first; the second waits for a use.

## 10. Ruby's syntax, tape semantics

Every Ruby and Crystal form stays as written; the compiler places the
memory. A program is written as in Ruby; what differs is where its data
lives, not how it is spelled.

Each written form, and what the compiler does with it:

* `s << "x"`: appends in place when `s` tops its tape; otherwise builds
  `s + "x"` on the tape and rebinds `s`.
* `s.upcase!`, `s.strip!`: `s = s.upcase`, a rebinding as above.
* `[[1, 2], [3]]`: the inner arrays are runs of a `SlicePool` the outer
  array owns. `outer[0]` answers a handle to its run, not a copy: after
  `inner = outer[0]; inner << 1`, `outer[0]` shows the 1, as in Ruby. A
  run may move as it grows, so no view into it outlives the next growth
  (the compiler refuses one, as Goose §5.1 does).
* `Hash(K, Array(V))`, `group_by`: the values are handles to runs of a
  `SlicePool` the hash owns, as above.
* `CACHE << x`, `@@seen[k] = v`: a long-lived container (a constant, a
  class variable, a field of a program-owned object) owns a `SlicePool`
  for what it holds. A store copies the value into a run of that pool;
  `delete`, `clear` and an overwrite give the run back, so memory kept
  across requests is reused, never leaked. Nothing goes to `Program.tape`
  by accident: it holds only what is built once and kept to the end.
* `@field = value` on an object that lives longer than the value: the
  compiler refuses it and names the forms that work: `copy_to(owner)`, or
  holding the value in a long-lived container. Copies stay visible where
  their cost is not bounded by one store.
* `x.to_s`, `String.new`, `.dup`: built on the current tape.
* `x.to_heap`: a copy onto the current tape, kept for old code.
* A task's value and a board message: copied to the reader, as now.

* A copy happens only at a store into a long-lived container, into its
  own pool. Inside one scope nothing is copied; a store anywhere else that
  would outlive its tape is a compile error naming `copy_to`.
* One visible difference: a `String` is immutable, so after `t = s;
  s << "x"`, `t` is still the old text (Ruby would show it changed in
  both). The same holds for `upcase!` and the other bang methods.
* A long-running server keeps data across requests in a long-lived
  container; its memory is the container's pool, freed by `delete`,
  `clear` or an overwrite. A container that only grows is the program's
  choice, visible as its size, not a hidden leak.
