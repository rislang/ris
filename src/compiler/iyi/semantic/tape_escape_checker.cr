# Tape-only code retains values through explicit owners. Raw allocation
# calls are rejected with the supported replacement.
class Iyi::TapeEscapeChecker
  @program : Program
  @seen = Set(UInt64).new
  @defs = [] of Def

  def initialize(@program)
  end

  def run(node : ASTNode) : Nil
    node.accept Collector.new(self)
    node.accept Finder.new(self)
    @defs.each do |a_def|
      a_def.body.accept Finder.new(self)
    end
  end

  def reach(a_def : Def) : Nil
    return if TapeRules.runtime?(@program, a_def.location) || !@seen.add?(a_def.object_id)
    @defs << a_def
    a_def.body.accept Collector.new(self)
  end

  # General allocation has no representation in the tape-only runtime.
  def refuse?(node : Call) : String?
    return nil if TapeRules.runtime?(@program, node.location)
    if node.type?.try(&.to_s) == "RisPoolStorage"
      return "pool storage is private; use Array(T).new(capacity)"
    end
    if node.name.in?("__pool_copy", "__release_run", "__remove_slot")
      return "pool handles are private; store arrays in Array or Hash"
    end
    if node.name.in?("malloc", "realloc") && (receiver = node.obj.try(&.type?))
      receiver = receiver.instance_type if receiver.metaclass?
      if receiver.is_a?(PointerInstanceType)
        return "General allocation is unavailable; use Array or a\n" \
               "typed Pool/SlicePool owner; use copy_to(owner) to retain data"
      end
    end
    nil
  end

  class Collector < Visitor
    def initialize(@checker : TapeEscapeChecker)
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
    def initialize(@checker : TapeEscapeChecker)
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      if reason = @checker.refuse?(node)
        node.raise reason
      end
      true
    end

    def visit(node : StringInterpolation)
      node.expanded.try &.accept self
      false
    end

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end
end
