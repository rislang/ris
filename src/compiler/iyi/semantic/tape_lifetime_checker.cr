# Follow calls and their lexical block bindings, not just the syntax inside
# Tape.run. A helper can yield to a caller whose locals outlive its tape.
class Iyi::TapeLifetimeChecker < Iyi::Visitor
  class BlockContext
    getter block : Block
    getter parent : BlockContext?
    getter owner : Def?
    getter scope : Block?

    def initialize(@block, @parent, @owner, @scope)
    end
  end

  # AST equality compares syntax. Distinct instantiations with identical
  # syntax can have different tape types and must both be checked.
  record VisitKey, target : Def, scope : Block?, binding : BlockContext? do
    def ==(other : self)
      target.same?(other.target) && scope.same?(other.scope) && binding.same?(other.binding)
    end

    def hash(hasher)
      {target.object_id, scope.try(&.object_id), binding.try(&.object_id)}.hash(hasher)
    end
  end

  @local_tape = false
  @scope : Block? = nil
  @owner : Def? = nil
  @block : Block? = nil
  @yield_context : BlockContext? = nil
  @block_exit_safe = true
  @loop_depth = 0
  @contexts = Set(ASTNode).new.compare_by_identity
  @visited = Set(VisitKey).new
  @active = Set(Tuple(UInt64, UInt64?)).new

  def initialize(@program : Program)
  end

  def visit(node : Def)
    false # Only instantiated, reachable method bodies have lifetime meaning.
  end

  def visit(node : Call)
    if expanded = node.expanded
      expanded.accept self
      return false
    end
    node.obj.try &.accept self
    node.args.each &.accept self
    node.named_args.try &.each { |arg| arg.value.accept self }
    node.block_arg.try &.accept self
    if literal = node.block.try(&.fun_literal).as?(ProcLiteral)
      literal.accept self
    end

    if tape_scope?(node)
      local_tape = node.name == "local"
      if (local_tape || !@scope) && (type = node.type?) && TapeChecker.tape_in(@program, type)
        node.raise "cannot break a tape value out of its Tape.#{node.name}: its storage ends with the scope" + ownership_hint(type)
      end
      if block = node.block
        previous_scope, previous_local_tape = @scope, @local_tape
        previous_contexts = @contexts
        if local_tape
          @contexts = Set(ASTNode).new.compare_by_identity
          @scope = block
          @local_tape = true
        else
          @scope ||= block
        end
        visit_block(block, @owner, @yield_context, !local_tape && !previous_scope.nil?)
        @scope, @local_tape = previous_scope, previous_local_tape
        @contexts = previous_contexts
      end
      return false
    end

    if node.obj.nil? && node.target_defs.try(&.any? { |target| TapeChecker.tape?(@program, target.owner) })
      check_outer_self(node)
    end
    binding = node.block.try { |block| BlockContext.new(block, @yield_context, @owner, @scope) }
    node.target_defs.try &.each do |target|
      key = VisitKey.new(target, @scope, binding)
      active_key = {target.object_id, @scope.try(&.object_id)}
      next if @active.includes?(active_key) || !@visited.add?(key)
      @active.add(active_key)
      previous_owner, previous_block, previous_yield = @owner, @block, @yield_context
      previous_loop_depth = @loop_depth
      @loop_depth = 0
      @owner, @block, @yield_context = target, nil, binding
      added = @scope && @contexts.add?(target)
      target.body.accept self
      @contexts.delete(target) if added
      @owner, @block, @yield_context = previous_owner, previous_block, previous_yield
      @loop_depth = previous_loop_depth
      @active.delete(active_key)
    end
    false
  end

  # Keep the proposed repair valid for both text and tape-bearing DTOs.
  private def tape_scope_name : String
    @local_tape ? "Tape.local" : "Tape.run"
  end

  private def ownership_hint(type : Type) : String
    if type.remove_typedef.to_s == "Tape::String"
      "\n\nCopy the text with `.to_s` inside the owning #{tape_scope_name} to obtain a String that can outlive it."
    else
      "\n\nBuild an owned value before leaving the scope; copy contained Tape::String values with `.to_s`. Copying a tape-bearing struct alone does not copy its storage."
    end
  end

  private def tape_scope?(node : Call) : Bool
    return false unless node.name == "run" || node.name == "local"
    node.target_defs.try &.any? do |target|
      owner = target.owner
      owner.metaclass? && owner.instance_type.to_s == "Tape"
    end || false
  end

  def visit(node : Yield)
    if expanded = node.expanded
      expanded.accept self
      return false
    end
    node.exps.each &.accept self
    if binding = @yield_context
      visit_block(binding.block, binding.owner, binding.parent, !@scope.nil? && binding.scope.same?(@scope))
    end
    false
  end

  private def visit_block(block : Block, owner : Def?, binding : BlockContext?, exit_safe : Bool)
    previous_owner, previous_block, previous_yield = @owner, @block, @yield_context
    previous_exit_safe, previous_loop_depth = @block_exit_safe, @loop_depth
    @block_exit_safe, @loop_depth = exit_safe, 0
    @owner, @block, @yield_context = owner, block, binding
    added = @scope && @contexts.add?(block)
    block.body.accept self
    @contexts.delete(block) if added
    @owner, @block, @yield_context = previous_owner, previous_block, previous_yield
    @block_exit_safe, @loop_depth = previous_exit_safe, previous_loop_depth
  end

  # There is no region parameter in tape types yet. Conservatively forbid
  # access to an outer mutable tape value: a write through it could retain
  # local storage. Tape::String is immutable and safe to borrow for reads.
  # Raw pointer access remains explicitly outside tape lifetime guarantees.
  def visit(node : Var)
    if @local_tape && (type = node.type?) && TapeChecker.tape_in(@program, type) && type.remove_typedef.to_s != "Tape::String"
      meta = @block.try(&.vars.try(&.[node.name]?)) || @owner.try(&.vars.try(&.[node.name]?))
      context = meta.try &.context
      unless context.is_a?(ASTNode) && @contexts.includes?(context)
        node.raise "cannot use outer tape value `#{node.name}` inside Tape.local: it could retain temporary storage; copy it into owned data before entering (outer Tape::String values may be read)"
      end
    end
    false
  end

  private def check_outer_self(node : ASTNode)
    if @local_tape && (owner = @owner) && !@contexts.includes?(owner) && TapeChecker.tape?(@program, owner.owner) && owner.owner.to_s != "Tape::String"
      node.raise "cannot use outer tape value `self` inside Tape.local: copy it into owned data before entering"
    end
  end

  def visit(node : Self)
    check_outer_self(node)
    false
  end

  def visit(node : InstanceVar)
    check_outer_self(node)
    false
  end

  def visit(node : Assign)
    if @scope && node.target.is_a?(Var) && (type = node.value.type?) && TapeChecker.tape_in(@program, type)
      name = node.target.as(Var).name
      meta = @block.try(&.vars.try(&.[name]?)) || @owner.try(&.vars.try(&.[name]?))
      context = meta.try &.context
      unless context.is_a?(ASTNode) && @contexts.includes?(context)
        node.raise "`#{name}` is a variable of the code around this #{tape_scope_name}, and is assigned `#{type}` here: its storage ends with the scope, so the variable would outlive it" + ownership_hint(type)
      end
    end
    true
  end

  def visit(node : Return)
    if @scope && (type = node.exp.try(&.type?)) && TapeChecker.tape_in(@program, type)
      unless @owner.try { |owner| @contexts.includes?(owner) }
        node.raise "cannot return a tape value out of its #{tape_scope_name}: its storage ends with the scope" + ownership_hint(type)
      end
    end
    true
  end

  def visit(node : Break)
    if @scope && !@block_exit_safe && @loop_depth == 0 && (type = node.exp.try(&.type?)) && TapeChecker.tape_in(@program, type)
      node.raise "cannot break a tape value out of its #{tape_scope_name}: its storage ends with the scope" + ownership_hint(type)
    end
    true
  end

  def visit(node : While)
    node.cond.accept self
    @loop_depth += 1
    node.body.accept self
    @loop_depth -= 1
    false
  end

  def visit(node : ProcLiteral)
    # A proc can run later. Check its body independently; captures are checked
    # by CleanupTransformer, and do not borrow the creation site's tape.
    key = VisitKey.new(node.def, nil, nil)
    if @visited.add?(key)
      previous_scope, previous_owner, previous_block, previous_yield = @scope, @owner, @block, @yield_context
      previous_contexts, previous_local_tape = @contexts, @local_tape
      @contexts = Set(ASTNode).new.compare_by_identity
      @local_tape = false
      @scope, @owner, @block, @yield_context = nil, node.def, nil, nil
      node.def.body.accept self
      @scope, @owner, @block, @yield_context = previous_scope, previous_owner, previous_block, previous_yield
      @contexts, @local_tape = previous_contexts, previous_local_tape
    end
    false
  end

  def visit(node : ASTNode)
    true
  end
end
