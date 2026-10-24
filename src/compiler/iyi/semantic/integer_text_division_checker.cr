# ris: an integer `/` straight into text is refused. It gives a Float,
# so `"#{ticks / 10000}"` printed "0.0016" where "0" was meant: an agent's
# port wrote it, compiled, and printed wrong timings. `//` is integer
# division; `a.to_f / b` says a Float is meant, and is let through.
class Iyi::IntegerTextDivisionChecker
  @program : Program
  @seen = Set(UInt64).new

  def initialize(@program)
  end

  def run(node : ASTNode) : Nil
    node.accept Collector.new(self)
  end

  def reach(a_def : Def) : Nil
    return unless user_code?(a_def.location)
    return unless @seen.add?(a_def.object_id)
    a_def.body.accept Collector.new(self)
  end

  private def user_code?(location : Location?) : Bool
    file = location.try(&.original_filename)
    return false unless file
    file = File.expand_path(file).gsub('\\', '/')
    !file.ends_with?(".cr") &&
      !file.includes?("/src/iyi/") &&
      !file.includes?("/src/std/") &&
      !file.includes?("/src/compiler/")
  end

  def inspect_call(node : Call) : Nil
    return unless user_code?(node.location)
    if node.name == "to_s"
      warn_division(node.obj)
    elsif node.name == "interpolation" || node.name == "interpolate"
      string_call = node.target_defs.try do |defs|
        defs.any? do |target|
          owner = target.owner
          owner.metaclass? &&
            {"String", "Str"}.includes?(owner.instance_type.to_s)
        end
      end
      node.args.each { |arg| warn_division(arg) } if string_call
    end
  end

  private def warn_division(node : ASTNode?) : Nil
    return unless node.is_a?(Call) && node.name == "/"
    return unless node.args.size == 1
    left = node.obj.try(&.type?)
    right = node.args[0].type?
    return unless left.is_a?(IntegerType) && right.is_a?(IntegerType)
    node.raise "integer / in text gives a Float (`16 / 10000` is 0.0016).\n\n" \
               "Write `a // b` for integer division, or `a.to_f / b` when a Float is meant."
  end

  class Collector < Visitor
    def initialize(@checker : IntegerTextDivisionChecker)
    end

    def visit(node : Call)
      @checker.inspect_call(node)
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
end
