# B1: owners have one named binding. B2 supplies reference passing and
# destination construction; this pass deliberately changes no lowering.
class Iyi::TapeOwnerChecker
  getter program : Program

  def initialize(@program : Program)
  end

  def self.owner?(program : Program, type : Type) : Bool
    type = type.remove_typedef
    type = type.generic_type if type.is_a?(GenericClassInstanceType)
    type.is_a?(Annotatable) && !type.annotation(program.owner_annotation).nil?
  end

  def self.owner_in(program : Program, type : Type,
                    seen = Set(Type).new) : Bool
    type = type.remove_typedef
    return false unless seen.add?(type)
    return true if owner?(program, type)
    case type
    when UnionType
      type.union_types.any? { |t| owner_in(program, t, seen) }
    when TupleInstanceType
      type.tuple_types.any? { |t| owner_in(program, t, seen) }
    when NamedTupleInstanceType
      type.entries.any? { |e| owner_in(program, e.type, seen) }
    when ProcInstanceType
      false # A callable signature does not store its arguments or result.
    when PointerInstanceType
      owner_in(program, type.element_type, seen)
    when GenericClassInstanceType
      type.type_vars.values.any? do |v|
        v.is_a?(Var) && v.type?.try { |t| owner_in(program, t, seen) } == true
      end
    else
      false
    end
  end

  @seen = Set(UInt64).new

  def run(node : ASTNode) : Nil
    node.accept Finder.new(self)
    @program.const_initializers.each { |i| i.value.accept Finder.new(self, initial: i.value) }
    @program.class_var_initializers.each { |i| i.node.accept Finder.new(self, initial: i.node) }
  end

  def owner?(node : ASTNode) : Bool
    node.type?.try { |t| TapeOwnerChecker.owner?(@program, t) } == true
  end

  def composite?(node : ASTNode) : Bool
    node.type?.try do |t|
      !t.metaclass? && !TapeOwnerChecker.owner?(@program, t) &&
        TapeOwnerChecker.owner_in(@program, t)
    end == true
  end

  def reach(target : Def) : Nil
    return if target.body.is_a?(Primitive)
    return if TapeRules.runtime?(@program, target.location)
    return unless @seen.add?(target.object_id)
    # The compiler's generated constructor returns its fresh receiver.
    if target.name == "new" && target.type?.try { |t| TapeOwnerChecker.owner?(@program, t) }
      target.body.accept ConstructorCalls.new(self)
      return
    end
    target.body.accept Finder.new(self, target)
  end

  def refuse(node : ASTNode, why : String) : NoReturn
    node.raise "#{why}; borrow it: pass the owner variable. " \
               "Declare one owner per scope"
  end

  class ConstructorCalls < Visitor
    def initialize(@checker : TapeOwnerChecker)
    end

    def visit(node : Call)
      node.target_defs.try &.each { |d| @checker.reach(d) }
      true
    end

    def visit(node : ASTNode)
      true
    end
  end

  class Finder < Visitor
    @allowed = Set(UInt64).new
    @bindings = Set(String).new

    def initialize(@checker : TapeOwnerChecker, @def : Def? = nil,
                   initial : ASTNode? = nil)
      @allowed << initial.object_id if initial
      @def.try do |d|
        d.args.each { |a| @bindings << a.name }
        body = d.body
        body = TapeScopeChecker.parts(body).try(&.[1]) || body
        if @checker.owner?(body)
          @checker.refuse(body, "cannot return a local owner from a def")
        end
      end
    end

    def visit_any(node)
      return true if node.is_a?(Def)
      # Probes use fake values solely to instantiate the user's defs.
      # Check those bodies, not the probe's temporary union result.
      if node.is_a?(If) && node.iyi_definition_probe?
        node.accept ConstructorCalls.new(@checker)
        return false
      end
      if @checker.composite?(node)
        @checker.refuse(node, "cannot store an owner in a container, tuple or union: #{node.type?}")
      end
      true
    end

    def visit(node : Assign)
      bind(node, node.target, node.value)
      false
    end

    def visit(node : TypeDeclaration)
      if type = node.declared_type.type?
        type = type.instance_type
        if !TapeOwnerChecker.owner?(@checker.program, type) &&
           TapeOwnerChecker.owner_in(@checker.program, type)
          @checker.refuse(node, "cannot store an owner in a container, tuple or union")
        end
      end
      if value = node.value
        bind(node, node.var, value)
      end
      false
    end

    private def bind(node, target, value)
      if @checker.composite?(target)
        @checker.refuse(node, "cannot store an owner in a container, tuple or union")
      end
      if @checker.owner?(value)
        if !value.is_a?(Call)
          @checker.refuse(node, "cannot copy or reassign an owner")
        end
        if target.is_a?(Var)
          @checker.refuse(node, "cannot copy or reassign an owner") unless @bindings.add?(target.name)
        elsif target.is_a?(ClassVar)
          @checker.refuse(node, "cannot copy or reassign an owner") if target.type?
        elsif !target.is_a?(Path)
          @checker.refuse(node, "cannot store an owner in a field")
        end
        @allowed << value.object_id
      end
      value.accept self
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      if @checker.owner?(node) && !@allowed.includes?(node.object_id)
        @checker.refuse(node, "owner temporary requires a named declaration")
      end
      # TODO B2: pass named owner arguments by reference, then check
      # returned borrows. For now a Var argument is intentionally allowed.
      node.target_defs.try &.each { |d| @checker.reach(d) }
      if node.program_initializer?
        if block = node.block
          body = TapeScopeChecker.parts(block.body).try(&.[1]) || block.body
          if @checker.owner?(body) && !body.is_a?(Call)
            @checker.refuse(body, "cannot copy or reassign an owner")
          end
          @allowed << body.object_id
        end
      end
      true
    end

    def visit(node : Block)
      previous = @bindings
      @bindings = @bindings.dup
      node.args.each { |arg| @bindings << arg.name }
      node.body.accept self
      @bindings = previous
      false
    end

    def visit(node : Return)
      if exp = node.exp
        @checker.refuse(node, "cannot return a local owner from a def") if @checker.owner?(exp)
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
