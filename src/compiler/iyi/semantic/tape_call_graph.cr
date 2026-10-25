# One specialized graph for tape analyses. Runtime and untravelled artifact
# bodies remain opaque; all dispatch alternatives and lexical callbacks use
# the same collection policy. Effects only grow during the fixed point.
class Iyi::TapeCallGraph
  class Effect
    # Fresh growing result, not general allocation or suspension.
    property allocating = false
    property cyclic = false
    property shrink : TapeShrinkChecker::Summary?
  end

  getter program : Program
  getter defs = Hash(UInt64, Def).new
  getter effects = Hash(UInt64, Effect).new
  @edges = Hash(UInt64, Set(UInt64)).new
  @targets = Hash(UInt64, Array(Def)?).new
  @reachable = Hash(UInt64, Set(UInt64)).new

  def initialize(@program, node : ASTNode)
    node.accept Graph.new(self, nil)
    # Runtime callees are opaque bodies but can still execute a lexical
    # callback. Keep their outgoing callback edges in cycle reachability.
    @edges.each_key do |id|
      reached = Set(UInt64).new
      @edges[id].each { |to| collect_reachable(to, reached) }
      @reachable[id] = reached
      @effects[id]?.try { |effect| effect.cyclic = reached.includes?(id) }
    end
    loop do
      changed = false
      @defs.each_value do |target|
        summary = Result.new(self)
        fresh = summary.value(target.body)
        effect = @effects[target.object_id]
        if (fresh || summary.returns) && !effect.allocating
          effect.allocating = true
          changed = true
        end
      end
      break unless changed
    end
  end

  # Cache even absent targets: every consumer sees the same opaque call.
  def targets(call : Call) : Array(Def)?
    @targets.fetch(call.object_id) do
      @targets[call.object_id] = call.target_defs
    end
  end

  def reach(target : Def)
    return if TapeRules.runtime?(@program, target.location)
    return if target.iyi_from_artifact? && !target.iyi_body_travelled?
    return if @defs.has_key?(target.object_id)
    @defs[target.object_id] = target
    @effects[target.object_id] = Effect.new
    @edges[target.object_id] ||= Set(UInt64).new
    target.body.accept Graph.new(self, target)
  end

  def edge(owner : Def?, target : Def)
    if owner
      (@edges[owner.object_id] ||= Set(UInt64).new).add(target.object_id)
    end
    reach(target)
  end

  private def collect_reachable(from : UInt64, seen : Set(UInt64))
    return unless seen.add?(from)
    @edges[from]?.try &.each { |id| collect_reachable(id, seen) }
  end

  def cycle?(owner : Def, call : Call) : Bool
    targets(call).try(&.any? do |target|
      target.same?(owner) ||
        @reachable[target.object_id]?.try(&.includes?(owner.object_id)) == true
    end) || false
  end

  def growing?(node : ASTNode) : Bool
    growing_type?(node.type?)
  end

  private def growing_type?(type : Type?) : Bool
    return false unless type
    type = type.remove_typedef
    return type.union_types.any? { |t| growing_type?(t) } if type.is_a?(UnionType)
    name = type.to_s
    name == "Str::Builder" || name.starts_with?("Ary(") ||
      name.starts_with?("Tre(") || TapeOwnerChecker.owner?(@program, type)
  end

  def fresh?(node : ASTNode) : Bool
    return false unless growing?(node)
    if node.is_a?(Call)
      return fresh?(node.expanded.not_nil!) if node.expanded
      return true if {"new", "copy_to", "dup"}.includes?(node.name)
      allocated = targets(node).try(&.any? do |target|
        @effects[target.object_id]?.try(&.allocating) == true
      end) || false
      # A forwarding helper can return a fresh argument unchanged.
      allocated || node.obj.try { |obj| fresh?(obj) } == true ||
        node.args.any? { |arg| fresh?(arg) } ||
        node.block.try { |block| Result.new(self).value(block.body) } == true
    elsif node.is_a?(Cast)
      fresh?(node.obj)
    elsif node.is_a?(If) || node.is_a?(Expressions)
      Result.new(self).value(node)
    else
      false
    end
  end

  class Result
    getter returns = false
    @env = Hash(String, Bool).new

    def initialize(@checker : TapeCallGraph)
    end

    def value(node : ASTNode) : Bool
      case node
      when Expressions
        result = false
        node.expressions.each { |exp| result = value(exp) }
        result
      when Assign
        result = value(node.value)
        @env[node.target.as(Var).name] = result if node.target.is_a?(Var)
        result
      when TypeDeclaration
        result = node.value.try { |exp| value(exp) } || false
        @env[node.var.as(Var).name] = result if node.var.is_a?(Var)
        result
      when Var
        @env[node.name]? || false
      when Return
        result = node.exp.try { |exp| value(exp) } || false
        @returns ||= result
        result
      when If
        value(node.cond)
        before = @env.dup
        left = value(node.then)
        left_env = @env
        @env = before
        right = value(node.else)
        left_env.each { |name, fresh| @env[name] = fresh || @env[name]? || false }
        left || right
      when Cast
        value(node.obj)
      when Call
        return value(node.expanded.not_nil!) if node.expanded
        forwarded = node.obj.try { |obj| value(obj) } || false
        node.args.each do |arg|
          fresh = value(arg)
          forwarded ||= fresh
        end
        @checker.fresh?(node) || (@checker.growing?(node) && forwarded)
      else
        false
      end
    end
  end

  class Graph < Visitor
    def initialize(@checker : TapeCallGraph, @owner : Def?)
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      @checker.targets(node).try &.each do |target|
        @checker.edge(@owner, target)
        # A yielding callee executes the lexical callback on its call path.
        node.block.try &.body.accept Graph.new(@checker, target)
      end
      true
    end

    def visit(node : ProcLiteral)
      @checker.edge(@owner, node.def)
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
