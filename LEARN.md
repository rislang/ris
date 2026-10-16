# Learning ris: read this before writing code

For an agent that is to write ris. Read the source first, then build.

## 1. Get the source and read, in this order

`git clone https://github.com/rislang/ris`, then:

1. `README.md`: what ris is, and the tape example.
2. This file: the rules that differ from Ruby and Crystal.
3. `TAPE_DESIGN.md`: where a tape value may and may not go.
4. `samples/ris/hello.ri` and `samples/ris/shop/order.ri`: a program and
   a module it imports. `test/ris/*.ri` are small cases; `test/ris/refused/`
   is what the compiler rejects, one file per tape rule.
5. `SPEC.md` (iyi's, long): look things up, don't read it through. Part I
   is the rules (R-1..R-5); III.1 is errors; III.4 is fibers and channels.

## 2. The language, in short

Ruby's syntax with Crystal's types, blocks, unions and nil-safety, plus:

* A file is a module: `.ri`, first line `module shop/order`. Its path is
  the import path; there is no `require`.
* `import shop/order` (names stay `order::f`), `import shop/order::{f, T}`,
  `import shop/order::*`; a URL works too: `import github.com/x/y::{Y}`.
* `pub` exports. Every `pub def` writes all parameter and return types.
* Classes are closed: no reopening. `impl Trait for Type` lives in the
  trait's module or the type's.
* Errors are union members, no exceptions to catch:

```crystal
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
  "age #{parse_age(text)!}"           # `!` returns the error to the caller
end

puts greet("41").or_panic             # => age 41
case r = greet("x")
in String     then puts r
in ParseError then puts it.message    # `it` is the narrowed value
end
```

* Memory: ordinary objects use the GC. For bounded work (a request) use
  `Tape.scope do … end` with `TapeString`, `TapeWriter`, `TapeArray(T)`
  and `@[OnTape]` structs; `to_s` copies out what must survive the block.
* Tape only where it pays: a hot path that allocates much short-lived
  data. Elsewhere plain ris is simpler, and copy-out can cost more than
  it saves. Measure it yourself: run the real work with and without tape
  (`--release`, median of several runs), compare time and peak memory.
  Keep tape only for a clear gain.

## 3. Then install, and work in the loop

Needs Crystal and LLVM. In the clone: `make ris`, then
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
