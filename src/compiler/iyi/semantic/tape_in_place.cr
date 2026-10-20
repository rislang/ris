# ris: Goose builds a result at its final destination. A def whose value
# is `Tape::String.build do |w| ... end`, in ris's own code, gets a twin
# that writes into a writer it is given:
#
#   def render(x) : Tape::String          def __into_render(__dest, x) : Nil
#     Tape::String.build do |w|             w = __dest
#       w.append(x)                          w.append(x)
#     end                                    nil
#   end                                    end
#
# and `page.append(render(x))` calls the twin with `page` when `page` is
# a `Tape::String::Writer`: the text is written once, where it ends up,
# rather than built on the tape and copied. A name some def has with no
# twin is never called so.
module Iyi
  class Program
    # Each def name of ris's own code: whether every def by that name has
    # a twin.
    getter tape_into = {} of String => Bool
    # The plain `append`s these calls fall back to, never lowered again.
    getter tape_into_plain = Set(UInt64).new
  end

  module TapeInPlace
    PREFIX = "__into_"

    def self.twin(program : Program, node : Def) : Def?
      return nil if TapePointerCheckerLibrary.library?(node.location)
      name = node.name
      return nil if name.starts_with?(PREFIX)
      twin = make(node) if name.each_char.all? { |c| c.alphanumeric? || c == '_' || c == '?' }
      program.tape_into[name] = !twin.nil? && program.tape_into.fetch(name, true)
      twin
    end

    private def self.make(node : Def) : Def?
      return nil if node.block_arg || node.uses_block_arg? || node.splat_index || node.double_splat
      body = node.body
      statements = body.is_a?(Expressions) ? body.expressions : [body]
      last = statements.last?
      return nil unless last.is_a?(Call) && last.name == "build" && last.args.empty?
      path = last.obj
      return nil unless path.is_a?(Path) && path.names == ["Tape", "String"]
      block = last.block
      return nil unless block && block.args.size == 1
      dest = Arg.new("__dest", restriction: Path.global(["Tape", "String", "Writer"]))
      lines = statements[0...-1].map(&.clone)
      lines << Assign.new(Var.new(block.args.first.name), Var.new("__dest"))
      lines << block.body.clone
      lines << NilLiteral.new
      args = [dest] + node.args.map(&.clone)
      twin = Def.new(PREFIX + node.name, args, Expressions.new(lines))
      twin.receiver = node.receiver.clone
      twin.visibility = node.visibility
      twin.location = node.location
      twin
    end

    # `dest.append(call(args))`, the call's name with twins everywhere.
    def self.lower(program : Program, node : Call) : ASTNode?
      return nil unless node.name == "append" && node.args.size == 1 && node.block.nil?
      return nil if program.tape_into_plain.includes?(node.object_id)
      dest = node.obj
      inner = node.args.first
      return nil unless dest && inner.is_a?(Call) && inner.block.nil? && inner.named_args.nil?
      return nil unless program.tape_into[inner.name]?
      return nil if TapePointerCheckerLibrary.library?(node.location)
      temp = program.new_temp_var.at(node)
      writer = Path.global(["Tape", "String", "Writer"]).at(node)
      into = Call.new(inner.obj.clone, PREFIX + inner.name, [temp.clone] + inner.args.map(&.clone)).at(inner)
      fallback = Call.new(temp.clone, "append", inner.clone).at(node)
      program.tape_into_plain << fallback.object_id
      check = IsA.new(temp.clone, writer).at(node)
      Expressions.new([
        Assign.new(temp, dest).at(node),
        If.new(check, into, fallback).at(node),
      ] of ASTNode).at(node)
    end
  end
end
