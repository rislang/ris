# Activation-owned growing storage at specialized cycles (Goose §7.8).
class Iyi::TapeRecursionChecker
  getter program : Program

  def initialize(@program, @graph : TapeCallGraph)
  end

  def run(node : ASTNode)
    @graph.defs.each_value do |target|
      next if TapeRules.unsafe?(@program, target)
      Body.new(self, target).run
    end
  end

  def cycle?(owner : Def, call : Call) : Bool
    @graph.cycle?(owner, call)
  end

  def growing?(node : ASTNode) : Bool
    @graph.growing?(node)
  end

  def fresh?(node : ASTNode) : Bool
    @graph.fresh?(node)
  end

  class Body
    alias Guards = Array(Tuple(UInt64, Bool))
    record Event, node : ASTNode, name : String?, read : Bool,
      guards : Guards, owned : Bool = false
    @guards = Guards.new
    @events = [] of Event
    @aliases = Hash(String, Set(String)).new
    @pending = false
    @constructing = 0
    @calls = [] of Tuple(Call, Int32, Bool, Guards)

    def initialize(@checker : TapeRecursionChecker, @owner : Def)
    end

    def run
      walk(@owner.body, true)
      @calls.each do |call, at, pending, guards|
        live = @events[0...at].find do |born|
          name = born.name
          name && born.owned && compatible?(born.guards, guards) &&
            @events[at..].any? do |event|
              event.read && event.name == name &&
                compatible?(event.guards, guards) &&
                compatible?(event.guards, born.guards)
            end
        end.try(&.name)
        if live || pending
          detail = live ? "local `#{live}`" : "temporary or pending result"
          call.raise "cannot recurse with growing tape #{detail} live across the call: " \
                     "pass scratch owned outside the cycle (an Ary, Str::Builder or owner parameter), " \
                     "or end the local's use before the call"
        end
      end
    end

    private def compatible?(a : Guards, b : Guards) : Bool
      !a.any? { |x| b.any? { |y| x[0] == y[0] && x[1] != y[1] } }
    end

    private def assign(target : ASTNode, value : ASTNode)
      start = @events.size
      walk(value)
      return unless target.is_a?(Var)
      name = target.name
      if @checker.fresh?(value)
        @aliases[name] = Set{name}
      elsif source = value.as?(Var)
        @aliases[name] = @aliases[source.name]? || Set{source.name}
      elsif (type = value.type?) && TapeChecker.tape_in(@checker.program, type)
        @aliases[name] = @events[start..].compact_map(&.name).to_set
      else
        @aliases.delete(name)
      end
      @events << Event.new(target, name, false, @guards.dup, @checker.fresh?(value))
    end

    def walk(node : ASTNode, tail = false)
      # Scope marks save the body's result in a compiler temporary. That
      # assignment is still the def's return destination, not user scratch.
      if parts = TapeScopeChecker.parts(node)
        walk(parts[1], tail)
        return
      end
      case node
      when Expressions
        inherited = @pending
        node.expressions.each_with_index do |exp, i|
          @pending = inherited
          walk(exp, tail && i == node.expressions.size - 1)
        end
        @pending = inherited
      when Cast
        walk(node.obj, tail)
      when ExceptionHandler
        walk(node.body, tail)
        node.rescues.try &.each { |rescue_node| walk(rescue_node.body, tail) }
        node.else.try { |exp| walk(exp, tail) }
        node.ensure.try { |exp| walk(exp) }
      when Return
        node.exp.try { |exp| walk(exp, true) }
      when If
        walk(node.cond)
        pending = @pending
        aliases = @aliases.dup
        @guards << {node.object_id, true}
        walk(node.then, tail)
        left_pending = @pending
        @guards.pop
        left = @aliases
        @aliases = aliases
        @pending = pending
        @guards << {node.object_id, false}
        walk(node.else, tail)
        @guards.pop
        left.each do |name, roots|
          @aliases[name] = roots | (@aliases[name]? || Set(String).new)
        end
        @pending ||= left_pending
      when Assign
        assign(node.target, node.value)
      when TypeDeclaration
        node.value.try { |value| assign(node.var, value) }
      when Var
        (@aliases[node.name]? || Set{node.name}).each do |name|
          @events << Event.new(node, name, true, @guards.dup)
        end
      when Call
        if expanded = node.expanded
          walk(expanded, tail)
          return
        end
        return unless node.type?
        growing = @checker.growing?(node)
        fresh = @checker.fresh?(node)
        cycle = @checker.cycle?(@owner, node)
        @constructing += 1 if fresh && !cycle
        operand_start = @events.size
        node.obj.try { |obj| walk(obj) }
        node.args.each { |arg| walk(arg) }
        node.named_args.try &.each { |arg| walk(arg.value) }
        node.block_arg.try { |arg| walk(arg) }
        operands = @events[operand_start..].select(&.read).uniq(&.name)
        if cycle
          pending = @pending || @constructing > 0 || (growing && !tail)
          @calls << {node, @events.size, pending, @guards.dup}
        end
        # Evaluated operands remain live while later operands and the
        # callee run, even if their last syntactic read preceded the call.
        @events.concat(operands)
        node.block.try { |block| walk(block.body) }
        @constructing -= 1 if fresh && !cycle
        @pending ||= fresh
      when ProcLiteral
        # Also check the lexical activation: captured locals remain owned
        # by the surrounding def when its callback calls into the cycle.
        pending = @pending
        walk(node.def.body)
        @pending = pending
      when Def
        # Reachable specialized bodies are checked by the graph collector.
      else
        node.accept Children.new(self, node)
      end
    end

    class Children < Visitor
      def initialize(@body : Body, @root : ASTNode)
      end

      def visit(node : ASTNode)
        return true if node.same?(@root)
        @body.walk(node)
        false
      end
    end
  end
end
