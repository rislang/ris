# Learning ris: read this before writing code
## 1. Get the source and read, in this order
`git clone https://github.com/rislang/ris`, then:
1. `README.md`: what ris is, and the tape example.
2. This file: the rules that differ from Ruby and Crystal.
3. `SPEC.md`: ris's specification; `doc/TAPE_API.md`: examples.
4. `samples/ris/report.ri`: tape written by hand; `samples/ris/hello.ri`
   and `shop/order.ri`: a program and a module it imports. `test/ris/*.ri`
   are small cases; `test/ris/refused/` is what the compiler rejects.
5. [iyi references](doc/reference/iyi/README.md): unchanged language and
   library rules. Check snapshot version notes; look up only what you need.
## 2. The language, in short
Text parameters take `String` and borrow it; nothing copies it to accept it.

* A file is a module: `.ri`, first line `module shop/order`. Its path is
  the import path; there is no `require`.
* `import shop/order` (names stay `order::f`), `import shop/order::{f, T}`,
  `import shop/order::*`; a URL works too: `import github.com/x/y::{Y}`.
* `pub` exports. Every `pub def` writes all parameter and return types.
* No reopening: classes are closed; `impl` goes in the trait's or type's module.
* No pointers: `s[i]`, `s.byte_at(i)`, `s[a, n]`; a C module is `@[Ffi]`, a
  def `@[PointerUnsafe("why")]`; `forbid ffi, pointer_unsafe` in ris.mod.
* Errors are union members, no exceptions to catch:

```crystal
@[OnTape]
pub struct ParseError
  getter message : String
  def initialize(@message : String)
  end
end
impl Error for ParseError
end

pub def parse_age(text : String) : Int32 | ParseError
  age = text.to_i?
  return ParseError.new("not a number: #{text}") unless age
  age
end

def greet(text : String) : String | ParseError
  "age #{parse_age(text)!}" # `!` returns an error
end

puts greet("41").or_panic             # => age 41
case r = greet("x")
in String     then puts r
in ParseError then puts it.message    # `it` is the narrowed value
end
```

* Memory: main and every spawned fiber have an implicit owning tape.
  Literals are static `String` views; interpolation builds a `String` there.
  A `String` reads as in Ruby (`[a..]`, `split`, `index`, `to_i`) and is
  read-only; `s << x` on a local or field grows it in place. `Array(T)`,
  `Hash`, `RisTree(T)`, `@[OnTape]` structs and classes hold the rest, all on
  the tape: no heap, no GC. `copy_to(owner)` copies what must outlive its
  scope (`Program.tape`); `File.copy_to(Program.tape, path)` reads a kept
  file there without a second copy. A nested `tape` shares it. Every def,
  loop round and block frees its temporaries when it ends; keeping one past
  its end is
  a compile error naming the safe form (SPEC 1.1, 3.6).
* A def's result is built in its caller's scope: end the def with the call,
  grow a local and return it, or append to a parameter (SPEC 1.5, 1.9).
* A class with a growing field (`Array`, `RisTree`, a builder) is an owner:
  build it only as `x = T.new` at a named declaration, then pass and alias
  it freely; a def never returns its own local one (SPEC 2.1).

Byte pools: `read_bytes_at(UInt32, at)`, `write_bytes_at(at, v)`, append
`write_bytes(v)`; no byte loops. Lines: `read_line_tape` on the tape. Integer
`/` in text is refused (a Float): `a // b`, or `a.to_f / b` for a Float.
Lexers: `String::Scanner` (`current_byte`, `advance`, `scan`, `skip`) holds text
and offset; `ris check` warns of an `@pos += 1` that indexes tape text.
## 3. Then install, and work in the loop

Needs Crystal and LLVM 23. In the clone: `make ris`, then
`./bin/ris run samples/ris/hello.ri`. To install, follow README.md.

* `ris init example.com/me/app` writes `ris.mod` and `app.ri`;
  `ris get github.com/x/y` adds a requirement.
* After every edit: `ris check -f json FILE` (errors, with suggested
  edits), `ris fix FILE`, `ris fmt`, `ris test` (runs every `*_test.ri`;
  exit 0 passes). A test is a program: `import app::*`, then
  `exit 1 unless parse_age("7") == 7`.
* `ris doc MODULE` prints a module's exported surface: read that, not its
  body. `ris mcp` serves check, fix, context and test as MCP tools.
* `ris help` and `ris COMMAND --help` say the rest.
