# ris: a tape container made anew where an old one was, outside
# `initialize`. `@queue = Tape::Array(Token).new` in a method a loop calls
# compiles and runs right, and every array it replaces stays on the tape
# until the tape block ends: a tokenizer that did it once per token kept
# 110 MB for a 4.5 MB page and parsed it 40% slower. The tape frees
# nothing early, so the fix is the array's own `clear`, which keeps its
# room. A warning rather than an error: a method run once per scope, or
# an array handed out before it is replaced, may mean it. A writer is not
# asked about: the strings `finish` handed out view its bytes, so a new
# one is what keeps them (`clear` would write over them).
class Iyi::TapeRefillChecker
  @program : Program
  @seen = Set(UInt64).new
  @defs = [] of Def

  def initialize(@program)
  end

  def run(node : ASTNode) : Nil
    node.accept Collector.new(self)
    @defs.each { |a_def| a_def.body.accept Finder.new(self, a_def) }
  end

  def reach(a_def : Def) : Nil
    return if TapePointerCheckerLibrary.library?(a_def.location) || !@seen.add?(a_def.object_id)
    @defs << a_def
    a_def.body.accept Collector.new(self)
  end

  def check(node : Assign, a_def : Def) : Nil
    return if a_def.name == "initialize"
    target = node.target
    return unless target.is_a?(InstanceVar)
    value = node.value
    return unless value.is_a?(Call) && value.name == "new"
    return unless tape_array?(value.type?)
    @program.warnings.add_warning(node, "`#{target.name}` is given a new Tape::Array in `#{a_def.name}`, not in `initialize`: the one it held stays on the tape until the tape block ends, one for every call.\n\nWhen nothing else holds the old one, empty it with `#{target.name}.clear` and fill it again, which keeps its room.")
  end

  private def tape_array?(type : Type?) : Bool
    return false unless type
    type.remove_typedef.to_s.starts_with?("Tape::Array(")
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

  class Finder < Visitor
    def initialize(@checker : TapeRefillChecker, @def : Def)
    end

    def visit(node : Assign)
      @checker.check(node, @def)
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
