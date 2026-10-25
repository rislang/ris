# Intraprocedural view liveness. Events follow evaluation order, including
# the use of earlier operands when their enclosing call finally runs.
# Specialized call summaries converge before checking view liveness.
class Iyi::TapeShrinkChecker
  alias Guards = Array(Tuple(UInt64, Bool))
  record View, root : UInt64, born : Int32, guards : Guards = Guards.new
  record Value, roots : Array(UInt64), views : Array(View),
    procs : Array(ProcLiteral) = [] of ProcLiteral
  record Use, views : Array(View), node : ASTNode, guards : Guards
  record Shrink, roots : Array(UInt64), at : Int32, node : Call, chain : String,
    guards : Guards
  record Summary, seeds : Array(UInt64), shrinks : Hash(UInt64, String), result : Value
  alias Env = Hash(String, Value)

  EMPTY  = Value.new([] of UInt64, [] of View)
  SHRINK = {"clear", "truncate", "pop", "pop?", "shift", "shift?",
            "pop_n", "resize", "delete_at", "delete", "reject!", "select!"}
  VIEWS = {"finish", "span", "slice", "[]", "[]?", "first", "first?",
           "last", "last?", "fetch", "values_at", "to_unsafe", "to_slice",
           "iterator", "each", "each_with_index", "each_byte", "each_line"}
  @seen = Set(UInt64).new
  @uses = [] of Use
  @shrinks = [] of Shrink

  @defs = [] of Def
  @summaries = Hash(UInt64, Summary).new
  @fields = Hash(Tuple(UInt64, String), UInt64).new
  @parents = Hash(UInt64, Tuple(UInt64, String)).new
  @next_root = 0_u64
  @returns = EMPTY
  @callback_chain = [] of String
  @active_procs = Set(UInt64).new
  @guards = Guards.new

  private def view(root : UInt64) : View
    View.new(root, @uses.size, @guards.dup)
  end

  private def shrink(roots : Array(UInt64), node : Call, chain : String)
    @shrinks << Shrink.new(roots, @uses.size, node, chain, @guards.dup)
  end

  private def compatible?(a : Guards, b : Guards) : Bool
    !a.any? { |x| b.any? { |y| x[0] == y[0] && x[1] != y[1] } }
  end

  private def chain(name : String) : String
    (@callback_chain + [name]).join(" -> ")
  end

  private def fresh : UInt64
    @next_root += 1
  end

  private def field_root(root : UInt64, name : String) : UInt64
    # Fold repeated fields onto their ancestor. Recursive calls can walk
    # arbitrarily deep containers; conflating these paths keeps the effect
    # domain finite and conservatively aliases their storage.
    ancestor = root
    while parent = @parents[ancestor]?
      return ancestor if parent[1] == name
      ancestor = parent[0]
    end
    @fields[{root, name}] ||= begin
      id = fresh
      @parents[id] = {root, name}
      id
    end
  end

  private def seed_env(target : Def, seeds : Array(UInt64)) : Env
    env = Env.new
    env["self"] = Value.new([seeds[0]], [] of View)
    target.args.each_with_index do |arg, i|
      env[arg.name] = reference?(arg) ? Value.new([seeds[i + 1]], [] of View) : EMPTY
    end
    env
  end

  private def translate(root : UInt64, summary : Summary,
                        inputs : Array(Value)) : Array(UInt64)
    if i = summary.seeds.index(root)
      input = inputs[i]? || EMPTY
      input.roots + input.views.map(&.root)
    elsif parent = @parents[root]?
      translate(parent[0], summary, inputs).map { |r| field_root(r, parent[1]) }
    else
      [] of UInt64
    end
  end

  def initialize(@program : Program)
  end

  def run(node : ASTNode)
    node.accept Collector.new(self)
    loop do
      changed = false
      @defs.each do |target|
        old = @summaries[target.object_id]
        @uses.clear
        @shrinks.clear
        @returns = EMPTY
        result = merge(value(target.body, seed_env(target, old.seeds)), @returns)
        effects = old.shrinks.dup
        @shrinks.each do |effect|
          effect.roots.each { |root| effects[root] ||= effect.chain }
        end
        # Local allocations cannot be exported as parameter effects.
        effects.reject! { |root, _| translate(root, old, old.seeds.map { |r| Value.new([r], [] of View) }).empty? }
        result = Value.new(result.roots, result.views.map { |v| View.new(v.root, 0) })
        updated = Summary.new(old.seeds, effects, merge(old.result, result))
        changed ||= updated != old
        @summaries[target.object_id] = updated
      end
      break unless changed
    end
    @defs.each do |target|
      check(target.body, seed_env(target, @summaries[target.object_id].seeds)) unless TapeRules.unsafe?(@program, target)
    end
    check(node)
  end

  def reach(target : Def)
    return if TapeRules.runtime?(@program, target.location)
    return if target.iyi_from_artifact? && !target.iyi_body_travelled?
    return unless @seen.add?(target.object_id)
    @defs << target
    seeds = Array(UInt64).new(target.args.size + 1) { fresh }
    @summaries[target.object_id] = Summary.new(seeds, Hash(UInt64, String).new, EMPTY)
    target.body.accept Collector.new(self)
  end

  private def contains_root?(roots : Array(UInt64), root : UInt64) : Bool
    return true if roots.includes?(root)
    if parent = @parents[root]?
      contains_root?(roots, parent[0])
    else
      false
    end
  end

  private def check(body : ASTNode, env = Env.new)
    @uses.clear
    @shrinks.clear
    @returns = EMPTY
    value(body, env)
    @shrinks.each do |shrink|
      @uses.each_with_index do |use, i|
        next if i < shrink.at
        next unless compatible?(shrink.guards, use.guards)
        if use.views.any? { |view| view.born <= shrink.at && compatible?(view.guards, shrink.guards) && contains_root?(shrink.roots, view.root) }
          shrink.node.raise "cannot shrink tape storage with a live view " \
                            "used at #{use.node.location} via #{shrink.chain}: copy the view first " \
                            "with copy_to(owner), finish using it before " \
                            "shrinking, or keep an index instead of a view"
        end
      end
    end
  end

  private def storage?(node : ASTNode) : Bool
    storage_type?(node.type?)
  end

  private def storage_type?(type : Type?) : Bool
    name = type.try(&.remove_typedef.to_s) || ""
    name == "Str::Builder" || name.starts_with?("Ary(") || name.starts_with?("Tre(")
  end

  private def reference?(node : ASTNode) : Bool
    return true if storage?(node)
    type = node.type?
    return false unless type
    name = type.remove_typedef.to_s
    name == "Str" || name == "Str::Span" || name.starts_with?("Ary::Link(") || name.includes?("View(") || name.includes?("Iterator") ||
      name.starts_with?("Pointer(") || !!TapeChecker.tape_in(@program, type)
  end

  private def merge(a : Value, b : Value) : Value
    Value.new((a.roots + b.roots).uniq, (a.views + b.views).uniq,
      (a.procs + b.procs).uniq)
  end

  private def use(v : Value, node : ASTNode)
    @uses << Use.new(v.views, node, @guards.dup)
  end

  def value(node : ASTNode, env : Env) : Value
    case node
    when Expressions
      result = EMPTY
      node.expressions.each { |exp| result = value(exp, env) }
      result
    when Var, InstanceVar
      v = env[node.name] ||= if node.is_a?(InstanceVar)
                               Value.new((env["self"]? || EMPTY).roots.map { |r| field_root(r, node.name).as(UInt64) }, [] of View)
                             elsif reference?(node)
                               Value.new([node.object_id], [] of View)
                             else
                               EMPTY
                             end
      use(v, node)
      v
    when Assign
      v = value(node.value, env)
      target = node.target
      if target.is_a?(Var) || target.is_a?(InstanceVar)
        env[target.name] = v
      end
      v
    when TypeDeclaration
      if exp = node.value
        v = value(exp, env)
        target = node.var
        env[target.name] = v if target.is_a?(Var)
        v
      else
        EMPTY
      end
    when Cast
      value(node.obj, env)
    when Call
      return value(node.expanded.not_nil!, env) if node.expanded
      # Specialized-out branches retain syntax without executable targets.
      return EMPTY unless node.type?
      receiver = node.obj.try { |obj| value(obj, env) } || env["self"]? || EMPTY
      args = node.args.map { |arg| value(arg, env) }
      named = Hash(String, Value).new
      node.named_args.try &.each do |arg|
        named[arg.name] = v = value(arg.value, env)
        args << v
      end
      node.block_arg.try { |arg| args << value(arg, env) }
      storage_receiver = node.obj.try { |obj| storage?(obj) } ||
                         node.target_defs.try &.any? { |target| storage_type?(target.owner) }
      if storage_receiver && SHRINK.includes?(node.name)
        shrink(receiver.roots, node, chain(node.name))
      end
      inputs = [receiver] + args
      call_result = EMPTY
      summarized = false
      incomplete_result = false
      targets = node.target_defs
      if targets && !targets.empty?
        targets.each do |target|
          if summary = @summaries[target.object_id]?
            summarized = true
            actuals = [receiver] + target.args.map_with_index do |arg, i|
              named[arg.external_name]? || args[i]? || EMPTY
            end
            summary.shrinks.each do |root, chain|
              roots = translate(root, summary, actuals)
              shrink(roots, node, chain("#{node.name} -> #{chain}"))
            end
            roots = summary.result.roots.flat_map { |r| translate(r, summary, actuals) }
            views = summary.result.views.flat_map { |v| translate(v.root, summary, actuals) }
            call_result = merge(call_result, Value.new(roots, views.map { |r| view(r) }))
          else
            incomplete_result = true
            unless TapeRules.runtime?(@program, target.location)
              inputs.each { |v| shrink((v.roots + v.views.map(&.root)).uniq, node, chain("#{node.name} (opaque)")) }
            end
          end
        end
      elsif !TapeRules.runtime?(@program, node.location)
        inputs.each { |v| shrink((v.roots + v.views.map(&.root)).uniq, node, chain("#{node.name} (unknown)")) }
      end
      # Arguments remain evaluated values until the call consumes them.
      use(receiver, node)
      args.each { |arg| use(arg, node) }
      derived = receiver
      args.each { |arg| derived = merge(derived, arg) }
      if block = node.block
        outer = env.dup
        yielded_views = derived.views
        if VIEWS.includes?(node.name)
          yielded_views += receiver.roots.map { |root| view(root) }
        end
        yielded = Value.new(derived.roots, yielded_views)
        block.args.each { |arg| outer[arg.name] = yielded }
        @callback_chain << "#{node.name} block"
        value(block.body, outer)
        @callback_chain.pop
        use(yielded, block)
        env.keys.each { |key| env[key] = merge(env[key], outer[key]? || EMPTY) }
      end
      inputs.each do |input|
        input.procs.each do |literal|
          unless @active_procs.add?(literal.object_id)
            shrink(derived.roots, node,
              chain("#{node.name} (recursive callback)"))
            next
          end
          captured = env.dup
          # The callback may receive any of the call's tape arguments.
          literal.def.args.each { |arg| captured[arg.name] = Value.new(derived.roots, derived.views) }
          @callback_chain << "#{node.name} proc"
          value(literal.def.body, captured)
          @callback_chain.pop
          @active_procs.delete(literal.object_id)
        end
      end
      if {"copy_to", "dup", "to_heap", "new"}.includes?(node.name)
        reference?(node) ? Value.new([node.object_id], [] of View) : EMPTY
      elsif summarized && reference?(node)
        call_result = merge(call_result, derived) if incomplete_result
        views = call_result.views.map { |v| view(v.root) }
        unless storage?(node)
          views += call_result.roots.map { |r| view(r) }
        end
        Value.new(call_result.roots, views)
      elsif reference?(node)
        views = derived.views
        if VIEWS.includes?(node.name) || !storage?(node)
          views = views + derived.roots.map { |root| view(root) }
        end
        Value.new(storage?(node) ? derived.roots : [] of UInt64, views)
      else
        EMPTY
      end
    when If
      value(node.cond, env)
      left, right = env.dup, env.dup
      @guards << {node.object_id, true}
      a = value(node.then, left)
      @guards.pop
      @guards << {node.object_id, false}
      b = value(node.else, right)
      @guards.pop
      (left.keys | right.keys).each { |key| env[key] = merge(left[key]? || EMPTY, right[key]? || EMPTY) }
      merge(a, b)
    when Return
      result = node.exp.try { |exp| value(exp, env) } || EMPTY
      @returns = merge(@returns, result)
      result
    when ProcLiteral
      Value.new([] of UInt64, [] of View, [node])
    when Def, FunDef, ClassDef, ModuleDef, Macro
      EMPTY
    else
      children = Children.new(self, env, node)
      node.accept children
      if reference?(node)
        use(children.result, node)
        children.result
      else
        EMPTY
      end
    end
  end

  class Children < Visitor
    getter result = EMPTY

    def initialize(@checker : TapeShrinkChecker, @env : Env, @root : ASTNode)
    end

    def visit(node : ASTNode)
      return true if node.same?(@root)
      @result = @checker.merge_child(@result, @checker.value(node, @env))
      false
    end
  end

  def merge_child(a : Value, b : Value) : Value
    merge(a, b)
  end

  class Collector < Visitor
    def initialize(@checker : TapeShrinkChecker)
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      node.target_defs.try &.each { |target| @checker.reach(target) }
      true
    end

    def visit(node : ProcLiteral)
      @checker.reach(node.def)
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
