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
    check_passed_on
  end

  # One argument of a back edge, growing storage only. *sources* are the
  # calling def's parameters it is rooted in ("self" too); nil: none known.
  record Edge, call : Call, from : Def, to : Def, parameter : String,
    sources : Set(String)?

  @edges = [] of Edge

  def back_edge(from : Def, call : Call, parameter : Def -> String?,
                sources : Set(String)?)
    @graph.targets(call).try &.each do |to|
      next unless @graph.reaches?(to, from)
      name = parameter.call(to)
      @edges << Edge.new(call, from, to, name, sources) if name
    end
  end

  # SPEC 3.5: a parameter is passed on when every back edge gives it what
  # flowed out of it. Storage from elsewhere, or from another parameter
  # of the same def (a swap), is refused at the call.
  private def check_passed_on
    flow = Hash({UInt64, String}, Set({UInt64, String})).new
    @edges.each do |edge|
      target = {edge.to.object_id, edge.parameter}
      edge.sources.try &.each do |source|
        (flow[{edge.from.object_id, source}] ||= Set({UInt64, String}).new) << target
      end
    end
    @edges.each do |edge|
      target = {edge.to.object_id, edge.parameter}
      from_target = flow_from(flow, target)
      sources = edge.sources
      passed = sources && sources.all? do |source|
        # A receiver that stays a receiver, itself or a field of it.
        next true if source == "self" && edge.parameter == "self"
        node = {edge.from.object_id, source}
        from_target.includes?(node) &&
          from_target.none? do |other|
            other[0] == node[0] && other[1] != node[1] &&
              flow_from(flow, other).includes?(node)
          end
      end
      next if passed
      edge.call.raise "cannot pass other growing storage to `#{edge.parameter}` " \
                      "on a call back into a cycle (SPEC 3.5)#{cycle_text(edge.from, edge.call)}: " \
                      "pass the parameter on as itself or a field or view of it, " \
                      "or give the cycle its storage from outside"
    end
  end

  private def flow_from(flow, start)
    seen = Set({UInt64, String}).new
    work = [start]
    while node = work.pop?
      next unless seen.add?(node)
      flow[node]?.try { |next_nodes| work.concat(next_nodes) }
    end
    seen
  end

  def cycle?(owner : Def, call : Call) : Bool
    @graph.cycle?(owner, call)
  end

  # The cycle *call* closes, by def names, at most eight shown.
  def cycle_text(owner : Def, call : Call) : String
    path = @graph.cycle_path(owner, call).map do |d|
      d.owner.try { |o| "#{o}##{d.name}" } || d.name
    end
    return "" if path.empty?
    path = path.first(4) + ["..."] + path.last(3) if path.size > 8
    " (the call reaches #{owner.name} again: #{path.join(" -> ")})"
  end

  def growing?(node : ASTNode) : Bool
    @graph.growing?(node)
  end

  def fresh?(node : ASTNode) : Bool
    @graph.fresh?(node)
  end

  def growing_self?(target : Def) : Bool
    (owner = target.owner?) ? TapeOwnerChecker.owner?(@program, owner) : false
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
    # A local's parameter roots; nil when any of it comes from elsewhere.
    @sources = Hash(String, Set(String)?).new

    def initialize(@checker : TapeRecursionChecker, @owner : Def)
    end

    def run
      @owner.args.each { |arg| @sources[arg.name] = Set{arg.name} }
      @sources["self"] = Set{"self"}
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
          call.raise "cannot recurse with growing tape #{detail} live across the call#{@checker.cycle_text(@owner, call)}: " \
                     "pass scratch owned outside the cycle (an Array, String::Builder or owner parameter), " \
                     "or end the local's use before the call"
        end
      end
    end

    # The parameters *node* is itself or a field or view of.
    private def roots(node : ASTNode) : Set(String)?
      case node
      when Var          then @sources[node.name]?
      when InstanceVar  then Set{"self"}
      when Cast         then roots(node.obj)
      when Expressions  then node.expressions.last?.try { |e| roots(e) }
      when If
        left = roots(node.then)
        right = roots(node.else)
        return right if node.then.is_a?(NilLiteral)
        return left if node.else.is_a?(NilLiteral)
        left && right ? left | right : nil
      when Call
        return roots(node.expanded.not_nil!) if node.expanded
        return nil if @checker.fresh?(node)
        (obj = node.obj) ? roots(obj) : Set{"self"}
      else
        nil
      end
    end

    private def note_back_edges(call : Call)
      if (obj = call.obj ? call.obj.not_nil! : nil).nil? || @checker.growing?(obj)
        if obj || @checker.growing_self?(@owner)
          @checker.back_edge(@owner, call, ->(_to : Def) { "self".as(String?) },
            obj ? roots(obj) : Set{"self"})
        end
      end
      call.args.each_with_index do |arg, i|
        next unless @checker.growing?(arg)
        @checker.back_edge(@owner, call, ->(to : Def) { to.args[i]?.try(&.name) }, roots(arg))
      end
      call.named_args.try &.each do |named|
        next unless @checker.growing?(named.value)
        @checker.back_edge(@owner, call, ->(to : Def) {
          to.args.find { |a| a.external_name == named.name }.try(&.name)
        }, roots(named.value))
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
      # `points << x` lowers to a rebind of the same growing local.
      unless @owner.args.any? { |arg| arg.name == name } &&
             value.to_s.includes?("RisTextGrowth")
        @sources[name] = roots(value)
      end
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
          note_back_edges(node)
          pending = @pending || @constructing > 0 || (growing && !tail)
          @calls << {node, @events.size, pending, @guards.dup}
        end
        # Evaluated operands remain live while later operands and the
        # callee run, even if their last syntactic read preceded the call.
        @events.concat(operands)
        node.block.try do |block|
          # A block's parameters hand out what its call was given.
          given = node.obj.try { |obj| roots(obj) }
          block.args.each { |arg| @sources[arg.name] = given }
          walk(block.body)
        end
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
