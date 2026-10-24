# ris: a warning, not a refusal, for a lexer that walks tape text by hand:
# an instance variable stepped with `@pos += n` (or `@pos = @pos + n`) and
# read as an index into a Str (`@text[@pos]`, `@text[@pos + 1]`).
# `Str::Scanner` keeps the text and its offset as one value and answers
# views with `scan`, `skip` and `check`; its `advance` costs what the add
# does. Indexing stays right and safe, so this is advice: one warning for
# each such variable of a type, at its first step. `std/` and the tape's
# runtime are not told.
class Iyi::TapeScannerHint
  @program : Program
  @seen = Set(UInt64).new
  @defs = [] of Def
  # Owner and variable name: where it is first stepped, and whether it is
  # read as an index into tape text.
  @steps = {} of {UInt64, String} => ASTNode
  @indexed = Set({UInt64, String}).new

  def initialize(@program)
  end

  def run(node : ASTNode) : Nil
    node.accept Collector.new(self)
    @defs.each do |a_def|
      owner = a_def.owner.object_id
      a_def.body.accept Finder.new(self, owner)
    end
    @steps.each do |key, node|
      next unless @indexed.includes?(key)
      name = key[1]
      @program.warnings.add_warning(node, "`#{name}` walks tape text by hand: it is stepped here and read as an index into a Str.\n\nStr::Scanner keeps the text and its offset as one value: `scan`, `skip` and `check` match at the offset and answer views, `current_byte` and `peek` look ahead, `advance` steps as `@pos += 1` does, at the same cost.")
    end
  end

  def reach(a_def : Def) : Nil
    return if TapeRules.runtime?(@program, a_def.location) || TapeRules.std?(a_def.location)
    return unless @seen.add?(a_def.object_id)
    @defs << a_def
    a_def.body.accept Collector.new(self)
  end

  def step(node : Assign, owner : UInt64) : Nil
    target = node.target
    return unless target.is_a?(InstanceVar)
    value = node.value
    return unless value.is_a?(Call) && value.name == "+"
    obj = value.obj
    return unless obj.is_a?(InstanceVar) && obj.name == target.name
    key = {owner, target.name}
    @steps[key] = node unless @steps.has_key?(key)
  end

  def index(node : Call, owner : UInt64) : Nil
    return unless node.name == "[]" && node.args.size == 1
    return unless node.obj.try(&.type?).try(&.remove_typedef.to_s) == "Str"
    arg = node.args[0]
    arg = arg.obj.not_nil! if arg.is_a?(Call) && {"+", "-"}.includes?(arg.name) && arg.obj
    @indexed << {owner, arg.name} if arg.is_a?(InstanceVar)
  end

  class Collector < Visitor
    def initialize(@hint : TapeScannerHint)
    end

    def visit(node : Call)
      node.target_defs.try &.each { |a_def| @hint.reach(a_def) }
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
    def initialize(@hint : TapeScannerHint, @owner : UInt64)
    end

    def visit(node : Assign)
      @hint.step(node, @owner)
      true
    end

    def visit(node : Call)
      @hint.index(node, @owner)
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
