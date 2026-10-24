require "../syntax/visitor"

# ris: a def short enough in the source is inlined wherever it is called,
# as `@[AlwaysInline]` would have it. LLVM decides on the def after its
# own passes, and by then a read like `span` (a varint: a loop, a `[]`,
# a `<<`) has its bounds and overflow checks peeled into five copies:
# cost 610 against a threshold of 250, so a ten-line helper stayed a
# call in the loops that use it, 8% of a JSON walk. Goose's C has none
# of those checks to count. A call from the top level is still kept out
# of line (`keep_call_out_of_main`): LLVM keeps a call marked noinline
# whatever the def says.
module Iyi::AutoInline
  # Nodes in a def's body, as normalized: `span`'s is 46. At 48 a
  # five-line program took 41s and 0.9GB to build --release, against 10s
  # and 0.4GB at 24, timing specs out and the compiler specs out of memory.
  LIMIT = (ENV["IYI_AUTO_INLINE"]? || "24").to_i

  def self.small?(a_def : Def) : Bool
    return false if LIMIT <= 0
    return false if a_def.no_inline? || a_def.always_inline? || a_def.naked? ||
                    a_def.returns_twice? || a_def.varargs?
    return false if a_def.block_arg || a_def.block_arity || a_def.uses_block_arg?
    # An error path (`fail`, `raise`'s helpers) is better left a call.
    return false if a_def.type?.try(&.no_return?)
    body = a_def.body
    return false if body.is_a?(Primitive) || body.is_a?(Nop)
    counter = Counter.new
    body.accept(counter)
    counter.count <= LIMIT
  end

  class Counter < Visitor
    getter count = 0

    # The body as written: a scope mark left off, the def's or a loop's,
    # is the same few nodes everywhere, and folds away.
    def visit(node : Expressions)
      if (parts = TapeScopeChecker.parts(node)) && !parts[0].value
        parts[1].accept(self)
        return false
      end
      @count += 1
      @count <= LIMIT
    end

    def visit(node : ASTNode)
      @count += 1
      @count <= LIMIT
    end
  end
end
