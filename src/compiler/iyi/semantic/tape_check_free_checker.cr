# ris: Goose's `checkfree fn`. A def marked `@[CheckFree]` may index only
# where no bound is checked: `each`, `map`, `sum`, `a[i]` in
# `while i < a.size` (TapeLoopBounds) and `Tape::Indexes`, whose indexes
# were checked once when they were made. A `[]` or `[]=` left in its body
# checks its bound at every call, and is refused with where it is.
class Iyi::TapeCheckFreeChecker
  INDEXING = {"[]", "[]?", "[]="}

  @seen = Set(UInt64).new

  def initialize(@program : Program)
  end

  def run(node : ASTNode) : Nil
    node.accept(Collector.new(self))
  end

  def reach(a_def : Def) : Nil
    return unless @seen.add?(a_def.object_id)
    if a_def.annotation(@program.check_free_annotation)
      a_def.body.accept(Finder.new(a_def.name))
    end
    a_def.body.accept(Collector.new(self))
  end

  class Collector < Visitor
    def initialize(@checker : TapeCheckFreeChecker)
    end

    def visit(node : Call)
      node.target_defs.try &.each { |a_def| @checker.reach(a_def) }
      true
    end

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end

  class Finder < Visitor
    def initialize(@name : String)
    end

    def visit(node : Call)
      if INDEXING.includes?(node.name) && node.obj
        node.raise "`#{@name}` is @[CheckFree], and this `#{node.name}` checks " \
                   "its index at every call.\n\nIndex in `while i < a.size` " \
                   "(i only `+= 1`), use `each`, `map` or `sum`, or check the " \
                   "indexes once where they come in: `target.indexes(array)` " \
                   "gives a Tape::Indexes that reads without a check."
      end
      true
    end

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end
end
