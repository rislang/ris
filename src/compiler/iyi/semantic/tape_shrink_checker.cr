# Intraprocedural view liveness. Events follow evaluation order, including
# the use of earlier operands when their enclosing call finally runs.
# Call effects and loop-carried roots are separate TODO increments.
class Iyi::TapeShrinkChecker
  record View, root : UInt64, born : Int32
  record Value, roots : Array(UInt64), views : Array(View)
  record Use, views : Array(View), node : ASTNode
  record Shrink, roots : Array(UInt64), at : Int32, node : Call
  alias Env = Hash(String, Value)

  EMPTY = Value.new([] of UInt64, [] of View)
  SHRINK = {"clear", "truncate", "pop", "pop?", "shift", "shift?",
            "pop_n", "resize", "delete_at", "delete", "reject!", "select!"}
  VIEWS = {"finish", "span", "slice", "[]", "[]?", "first", "first?",
           "last", "last?", "fetch", "values_at", "to_unsafe", "to_slice",
           "iterator", "each", "each_with_index", "each_byte", "each_line"}
  @seen = Set(UInt64).new
  @uses = [] of Use
  @shrinks = [] of Shrink

  def initialize(@program : Program)
  end

  def run(node : ASTNode)
    node.accept Collector.new(self)
    check(node)
  end

  def reach(target : Def)
    return if TapeRules.runtime?(@program, target.location)
    return unless @seen.add?(target.object_id)
    target.body.accept Collector.new(self)
    check(target.body) unless TapeRules.unsafe?(@program, target)
  end

  private def check(body : ASTNode)
    @uses.clear
    @shrinks.clear
    value(body, Env.new)
    @shrinks.each do |shrink|
      @uses.each_with_index do |use, i|
        next if i < shrink.at
        if use.views.any? { |view| view.born <= shrink.at && shrink.roots.includes?(view.root) }
          shrink.node.raise "cannot shrink tape storage with a live view " \
                            "used at #{use.node.location}: copy the view first " \
                            "with copy_to(owner), finish using it before " \
                            "shrinking, or keep an index instead of a view"
        end
      end
    end
  end

  private def storage?(node : ASTNode) : Bool
    name = node.type?.try(&.remove_typedef.to_s) || ""
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
    Value.new((a.roots + b.roots).uniq, (a.views + b.views).uniq)
  end

  private def use(v : Value, node : ASTNode)
    @uses << Use.new(v.views, node)
  end

  def value(node : ASTNode, env : Env) : Value
    case node
    when Expressions
      result = EMPTY
      node.expressions.each { |exp| result = value(exp, env) }
      result
    when Var, InstanceVar
      v = env[node.name] ||= storage?(node) ? Value.new([node.object_id], [] of View) : EMPTY
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
      receiver = node.obj.try { |obj| value(obj, env) } || EMPTY
      args = node.args.map { |arg| value(arg, env) }
      node.named_args.try &.each { |arg| args << value(arg.value, env) }
      node.block_arg.try { |arg| args << value(arg, env) }
      if node.obj.try { |obj| storage?(obj) } && SHRINK.includes?(node.name)
        @shrinks << Shrink.new(receiver.roots, @uses.size, node)
      end
      # Arguments remain evaluated values until the call consumes them.
      use(receiver, node)
      args.each { |arg| use(arg, node) }
      derived = receiver
      args.each { |arg| derived = merge(derived, arg) }
      if block = node.block
        outer = env.dup
        yielded = Value.new([] of UInt64, receiver.views + receiver.roots.map { |root| View.new(root, @uses.size) })
        block.args.each { |arg| outer[arg.name] = yielded }
        value(block.body, outer)
        use(yielded, block)
        env.keys.each { |key| env[key] = merge(env[key], outer[key]? || EMPTY) }
      end
      if {"copy_to", "dup", "to_heap", "new"}.includes?(node.name)
        storage?(node) ? Value.new([node.object_id], [] of View) : EMPTY
      elsif reference?(node)
        views = derived.views
        if VIEWS.includes?(node.name) || !storage?(node)
          views = views + receiver.roots.map { |root| View.new(root, @uses.size) }
        end
        Value.new(storage?(node) ? derived.roots : [] of UInt64, views)
      else
        EMPTY
      end
    when If
      value(node.cond, env)
      left, right = env.dup, env.dup
      a = value(node.then, left)
      b = value(node.else, right)
      (left.keys | right.keys).each { |key| env[key] = merge(left[key]? || EMPTY, right[key]? || EMPTY) }
      merge(a, b)
    when Def, FunDef, ClassDef, ModuleDef, Macro, ProcLiteral
      EMPTY
    else
      children = Children.new(self, env, node)
      node.accept children
      use(children.result, node)
      reference?(node) ? children.result : EMPTY
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
