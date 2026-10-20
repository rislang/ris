# ris: a value on the tape stays there until its scope ends. Text goes
# onto the tape freely (`Tape::String.new`, `Writer#append`), but back to
# the heap only by name: `to_heap`, or a `Tape::String`'s `to_s` in a def
# marked `@[TapeToHeap]`, where a value is handed to what outlives the
# tape - a cache, a broadcast, a record. So a request's text, once on
# its tape, is not copied off and carried on as a `String` by code between
# the intake and the response; each copy that leaves is at a boundary
# named as one. Interpolation and writing into a `String::Builder` or
# `IO::Memory` copy to the heap as `to_s` does, and are refused alike;
# writing to a file or a socket is not a copy. The library (`std/`,
# `src/iyi/`) is outside the rule: it keeps a `String` API beside the tape
# one, built by copying out.
class Iyi::TapeEscapeChecker
  @program : Program
  @seen = Set(UInt64).new
  @defs = [] of Def

  def initialize(@program)
  end

  def run(node : ASTNode) : Nil
    node.accept Collector.new(self)
    node.accept Finder.new(self, false)
    @defs.each do |a_def|
      a_def.body.accept Finder.new(self, escape?(a_def))
    end
  end

  def reach(a_def : Def) : Nil
    return if library?(a_def.location) || !@seen.add?(a_def.object_id)
    @defs << a_def
    a_def.body.accept Collector.new(self)
  end

  def escape?(a_def : Def) : Bool
    !a_def.annotation(@program.tape_to_heap_annotation).nil?
  end

  # As TapePointerChecker: a `std/` module wherever IYI_PATH finds it, and
  # the prelude with the tape itself.
  def library?(location : Location?) : Bool
    file = location.try(&.original_filename)
    return false unless file
    file = file.gsub('\\', '/')
    file.includes?("/std/") || file.includes?("/src/iyi/")
  end

  # Why the copy is refused, and what to write instead: the same for each
  # way of making it.
  WHY = <<-TEXT
    On the tape the text is freed with the whole tape at once, at no cost. \
    Each copy to the heap is a GC allocation and a copy of every byte, and \
    the GC must later find and free it; carried back onto the tape \
    (`append`, `Tape::String.new`) it is copied again. Code that goes \
    tape -> heap -> tape pays this at every turn and loses what the tape \
    saves: the respond sample takes 0.67 s on the tape, 1.55 s on the heap \
    (TAPE_DESIGN.md).

    Instead pass the Tape::String on; compare and slice it on the tape \
    (`==`, `starts_with?`, `[start, count]`); print it (`puts text`, \
    `io << text` to a file or socket); or append it to a \
    Tape::String::Writer. Only where the text must outlive the tape - a \
    cache, a broadcast, a record - copy it once, by name: `text.to_heap`, \
    or `to_heap` on a Tape::Array of it.
    TEXT

  def refuse?(node : Call) : String?
    return nil if library?(node.location)
    receiver = node.obj
    if node.name == "to_s" && node.args.empty? && !node.block &&
       tape_string?(receiver.try(&.type?))
      return "`to_s` of a Tape::String outside a @[TapeToHeap] def copies " \
             "the text to the GC heap.\n\n#{WHY}"
    end
    if heap_buffer?(receiver.try(&.type?)) &&
       node.args.any? { |arg| tape_string?(arg.type?) }
      return "Writing a Tape::String into a #{receiver.not_nil!.type} " \
             "outside a @[TapeToHeap] def copies the text to the GC heap." \
             "\n\n#{WHY}"
    end
    # `"#{text}"`, expanded to `String.interpolation(...)`.
    if node.name == "interpolation" &&
       receiver.try(&.type?).try(&.metaclass?) &&
       node.args.any? { |arg| tape_string?(arg.type?) }
      return "Interpolating a Tape::String outside a @[TapeToHeap] def " \
             "copies the text to the GC heap.\n\n#{WHY}"
    end
    if tape_string?(receiver.try(&.type?)) &&
       node.args.any? { |arg| heap_buffer?(arg.type?) }
      return "Writing a Tape::String into a String::Builder or " \
             "IO::Memory outside a @[TapeToHeap] def copies the text " \
             "to the GC heap.\n\n#{WHY}"
    end
    nil
  end

  private def tape_string?(type : Type?) : Bool
    return false unless type
    type.remove_typedef.to_s == "Tape::String"
  end

  # Where text written lands on the GC heap, unlike a file or a socket.
  private def heap_buffer?(type : Type?) : Bool
    return false unless type
    name = type.remove_typedef.to_s
    name == "String::Builder" || name == "IO::Memory" ||
      name == "Std::Io::Memory"
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
    def initialize(@checker : TapeEscapeChecker, @escape : Bool)
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      if !@escape && (reason = @checker.refuse?(node))
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
