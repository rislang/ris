# ris: inside a `tape` or `local_tape` block, or a def taking a tape
# value (a tape runs while one exists), `puts "a#{b}"` and
# `print "a#{b}"` write their text on the tape. The interpolation is
# made `Tape::String.interpolate(...)`, which appends each piece to a
# writer on the running tape; `puts` and `print` take a `Tape::String`.
# Nothing else changes: the text goes straight to the call, so no tape
# value is held anywhere new, and with no tape running (a proc called
# later) `interpolate` builds on the heap as before.
class Iyi::TapeTextLowering < Iyi::Visitor
  SINKS = {"puts", "print"}

  def self.tape_block?(node : Call) : Bool
    node.obj.nil? && !node.block.nil? &&
      (node.name == "tape" || node.name == "local_tape")
  end

  def self.tape_def?(node : Def) : Bool
    node.args.any? { |arg| arg.restriction.to_s.includes?("Tape::") }
  end

  def visit(node : Call)
    return true unless node.obj.nil? && SINKS.includes?(node.name)
    node.args.map! do |arg|
      if arg.is_a?(StringInterpolation)
        path = Path.global(["Tape", "String"]).at(arg)
        Call.new(path, "interpolate", arg.expressions).at(arg)
      else
        arg
      end
    end
    true
  end

  def visit(node : ASTNode)
    true
  end
end
