# ris: a tape array made anew where an old one was, outside `initialize`,
# is refused. `@queue = Ary(Token).new` in a method a loop calls
# compiles and runs right, and every array it replaces stays on the tape
# until the tape block ends: a tokenizer that did it once per token kept
# 110 MB for a 4.5 MB page and parsed it 40% slower. The tape frees
# nothing early, so the fix is the array's own `clear`, which keeps its
# room.
#
# Replacing it is right when the old one is handed on first, in the same
# def - `@rows << @row`, `batch = @items`, `return @items`, an argument -
# because then it is still in use and `clear` would empty it there too.
# Such a def is let through. A writer is not asked about: the strings
# `finish` handed out view its bytes, so a new one is what keeps them.
class Iyi::TapeRefillChecker
  @program : Program
  @seen = Set(UInt64).new
  @defs = [] of Def

  def initialize(@program)
  end

  def run(node : ASTNode) : Nil
    node.accept Collector.new(self)
    @defs.each do |a_def|
      next if a_def.name == "initialize" || a_def.name.starts_with?("initialize:")
      handed = HandOffs.new
      a_def.body.accept handed
      a_def.body.accept Finder.new(self, a_def, handed.reads)
    end
  end

  def reach(a_def : Def) : Nil
    return if TapeRules.runtime?(@program, a_def.location) || !@seen.add?(a_def.object_id)
    @defs << a_def unless TapeRules.unsafe?(@program, a_def)
    a_def.body.accept Collector.new(self)
  end

  def check(node : Assign, a_def : Def, reads : Array(InstanceVar)) : Nil
    target = node.target
    return unless target.is_a?(InstanceVar)
    value = node.value
    return unless value.is_a?(Call) && value.name == "new"
    return unless tape_array?(value.type?)
    return if reads.any? { |read| read.name == target.name && before?(read, node) }
    node.raise "`#{target.name}` is given a new Ary in `#{a_def.name}`, not in `initialize`: the one it held stays on the tape until the tape block ends, one for every call.\n\nEmpty it with `#{target.name}.clear` and fill it again, which keeps its room. When the old one is still wanted, hand it on first in this def (`list << #{target.name}`, `old = #{target.name}`, `return #{target.name}`) and the new one is allowed."
  end

  private def tape_array?(type : Type?) : Bool
    return false unless type
    type.remove_typedef.to_s.starts_with?("Ary(")
  end

  private def before?(read : ASTNode, node : ASTNode) : Bool
    a = read.location
    b = node.location
    return false unless a && b
    {a.line_number, a.column_number} < {b.line_number, b.column_number}
  end

  class Collector < Visitor
    def initialize(@checker : TapeRefillChecker)
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

  # Reads of an instance variable that hand its value on: a call's
  # argument, the value of an assignment, what a `return` answers. A read
  # as a call's receiver (`@items.size`) hands nothing on.
  class HandOffs < Visitor
    getter reads = [] of InstanceVar

    def visit(node : Call)
      node.args.each { |arg| take(arg) }
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      true
    end

    def visit(node : Assign)
      take(node.value)
      true
    end

    def visit(node : Return)
      node.exp.try { |exp| take(exp) }
      true
    end

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      true
    end

    private def take(node : ASTNode) : Nil
      @reads << node if node.is_a?(InstanceVar)
    end
  end

  class Finder < Visitor
    def initialize(@checker : TapeRefillChecker, @def : Def, @reads : Array(InstanceVar))
    end

    def visit(node : Assign)
      @checker.check(node, @def, @reads)
      true
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
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
