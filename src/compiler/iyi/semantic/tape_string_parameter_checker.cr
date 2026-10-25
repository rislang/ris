# Prefer borrowed text when a user parameter has no retaining use.
# Unknown calls and recursive flows count as retaining, never as proof.
class Iyi::TapeStringParameterChecker
  @seen = Set(UInt64).new
  @defs = [] of Def
  @active = Set({UInt64, Int32}).new

  def initialize(@program : Program)
  end

  def user?(a_def : Def) : Bool
    file = a_def.location.try(&.original_filename)
    !!file && file.ends_with?(".ri") &&
      !TapeRules.runtime?(@program, a_def.location) &&
      !TapeRules.std?(a_def.location)
  end

  def run(node : ASTNode) : Nil
    node.accept Collector.new(self)
    @defs.each do |a_def|
      next unless user?(a_def)
      a_def.args.each_with_index do |arg, index|
        restriction = arg.restriction
        nilable = restriction.is_a?(Union) &&
          restriction.types.size == 2 &&
          restriction.types.all? { |part|
            part.is_a?(Path) && part.names.in?([["String"], ["Nil"]])
          } && restriction.types.any? { |part|
            part.is_a?(Path) && part.names == ["Nil"]
          }
        next unless nilable ||
          (restriction.is_a?(Path) && restriction.names == ["String"])
        next if retains?(a_def, index)
        suffix = nilable ? "?" : ""
        arg.raise "#{arg.name} : String#{suffix} is only read; " \
                  "take it as Str#{suffix} " \
                  "(a String or a literal passes at no cost)"
      end
    end
  end

  def reach(a_def : Def) : Nil
    return unless @seen.add?(a_def.object_id)
    return if TapeRules.runtime?(@program, a_def.location)
    @defs << a_def
    a_def.body.accept Collector.new(self)
  end

  def retains?(a_def : Def, index : Int32) : Bool
    return true unless user?(a_def) && index < a_def.args.size
    return true if a_def.new? || a_def.name.starts_with?("initialize") ||
                   a_def.name.ends_with?("=")
    key = {a_def.object_id, index}
    return true unless @active.add?(key)
    nodes = Nodes.new
    a_def.body.accept nodes
    names = Set{a_def.args[index].name}
    loop do
      grew = false
      nodes.items.each do |node|
        next unless node.is_a?(Assign) && node.target.is_a?(Var)
        next unless contains?(node.value, names)
        grew = true if names.add?(node.target.as(Var).name)
      end
      break unless grew
    end
    retained = nodes.items.any? do |node|
      case node
      when Assign
        !node.target.is_a?(Var) && contains?(node.value, names)
      when Return
        node.exp.try { |exp| contains?(exp, names) } || false
      when ProcLiteral, Block, Yield
        contains?(node, names)
      when Call
        # Raw pointers may escape through operations this pass cannot model.
        next true if node.name == "to_unsafe" &&
                     node.obj.try { |obj| contains?(obj, names) }
        # A receiver may be yielded to a block under a different name.
        next true if node.block &&
                     node.obj.try { |obj| contains?(obj, names) }
        node.args.each_with_index.any? do |arg, i|
          next false unless contains?(arg, names)
          targets = node.target_defs
          next true unless targets && !targets.empty?
          targets.any? do |target|
            param = target.args[i]?
            next true unless param
            next false if param.type?.try(&.to_s) == "Str"
            retains?(target, i)
          end
        end
      else
        false
      end
    end
    # A String (or a container/proc holding it) returned implicitly may
    # carry an alias. Scalar results cannot retain the input text.
    # A declared String? result may retain text even when specialized to Nil.
    declared = a_def.return_type
    retained ||= declared.is_a?(Union) && declared.types.any? { |part|
      part.is_a?(Path) && part.names == ["String"]
    }
    result = a_def.body.type?
    if result && result != @program.nil &&
       !result.is_a?(PrimitiveType)
      tail = a_def.body
      tail = tail.expressions.last if tail.is_a?(Expressions)
      retained ||= contains?(tail, names)
    end
    @active.delete(key)
    retained
  end

  private def contains?(node : ASTNode, names : Set(String)) : Bool
    finder = Names.new(names)
    node.accept finder
    finder.found
  end

  class Collector < Visitor
    def initialize(@checker : TapeStringParameterChecker)
    end

    def visit(node : Call)
      node.target_defs.try &.each { |target| @checker.reach(target) }
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

  class Nodes < Visitor
    getter items = [] of ASTNode

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      @items << node
      true
    end

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      @items << node
      true
    end
  end

  class Names < Visitor
    getter found = false

    def initialize(@names : Set(String))
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      true
    end

    def visit(node : Var)
      @found ||= @names.includes?(node.name)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end
end
