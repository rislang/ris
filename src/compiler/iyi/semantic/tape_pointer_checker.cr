# ris: a `Tape::String`'s raw pointer stays in the library. Its
# `to_unsafe` compiles and then reads whatever follows its bytes - the next
# value, or, once the scope has ended, the next scope's - and
# `Tape::String.new(pointer, size)` makes a view of any address. The
# checkers that keep a tape value inside its scope do not see either, so
# outside a `std/` module and `src/iyi/` both are refused, and a program
# reads a tape string through the bounds-checked `[]`, `each_byte` and
# `[start, count]` instead. A raw pointer the program makes itself
# (`Pointer.new`) is outside this rule: iyi has no unsafe blocks for it.
class Iyi::TapePointerChecker
  @program : Program
  @seen = Set(UInt64).new
  @defs = [] of Def

  def initialize(@program)
  end

  def run(node : ASTNode) : Nil
    node.accept Collector.new(self)
    check node
    @defs.each { |a_def| check a_def.body }
  end

  def reach(a_def : Def) : Nil
    return if library?(a_def.location) || !@seen.add?(a_def.object_id)
    @defs << a_def
    a_def.body.accept Collector.new(self)
  end

  # Code of the library: a `std/` module, wherever IYI_PATH finds it (a
  # test's patched copy too), and the prelude with the tape itself.
  def library?(location : Location?) : Bool
    file = location.try(&.original_filename)
    return false unless file
    file.includes?("/std/") || file.includes?("/src/iyi/")
  end

  private def check(node : ASTNode) : Nil
    node.accept Finder.new(self)
  end

  def refuse?(node : Call) : String?
    return nil if library?(node.location)
    if node.name == "to_unsafe" && (receiver = node.obj) && tape_string?(receiver.type?)
      return "`to_unsafe` of a Tape::String outside the library: the pointer reads past its bytes as readily as within them, and after its scope the next scope's.\n\nRead it with `[]`, `[start, count]` or `each_byte`, which check their bounds."
    end
    if node.name == "new" && node.args.size == 2 && node.target_defs.try &.any? { |target| tape_string_class?(target.owner) }
      return "`Tape::String.new(pointer, size)` outside the library: a view of any address, which the tape's checks do not see.\n\nCopy a String onto the tape with `Tape::String.new(text)`, view one with `Tape::String.view(text)`, or a part of a tape string with `[start, count]`."
    end
    nil
  end

  private def tape_string?(type : Type?) : Bool
    return false unless type
    type.remove_typedef.to_s == "Tape::String"
  end

  private def tape_string_class?(owner : Type) : Bool
    owner.metaclass? && owner.instance_type.to_s == "Tape::String"
  end

  class Collector < Visitor
    def initialize(@checker : TapePointerChecker)
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
    def initialize(@checker : TapePointerChecker)
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

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end
end
