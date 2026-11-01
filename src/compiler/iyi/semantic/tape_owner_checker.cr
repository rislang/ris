# Owners are classes built at a named declaration; all other uses alias.
class Iyi::TapeOwnerChecker
  getter program : Program

  getter graph : TapeCallGraph

  def initialize(@program : Program, @graph : TapeCallGraph)
  end

  def self.owner?(program : Program, type : Type) : Bool
    type = type.remove_typedef
    type = type.base_type if type.is_a?(VirtualType)
    return false unless TapeChecker.class_instance?(program, type)
    return false unless type.is_a?(InstanceVarContainer)
    type.instance_vars.each_value.any? do |field|
      field.type?.try { |t| growing?(t) } == true && owns_storage?(field)
    end
  end

  # A handle borrowed from initialize's caller is a reference, not a
  # reservation belonging to the instance. Follow typed bindings to find
  # construction, including defaults and locals assigned to fields.
  private def self.owns_storage?(node : ASTNode,
                                 seen = Set(UInt64).new) : Bool
    return false unless seen.add?(node.object_id)
    # Reading a receiver's field borrows that receiver's reservation.
    return false if node.is_a?(InstanceVar)
    if node.is_a?(Call)
      return owns_storage?(node.expanded.not_nil!, seen) if node.expanded
      return true if {"new", "copy_to", "dup"}.includes?(node.name) &&
                     node.type?.try { |t| growing?(t) } == true
    end
    node.dependencies.any? { |source| owns_storage?(source, seen) }
  end

  private def self.growing?(type : Type, seen = Set(Type).new) : Bool
    type = type.remove_typedef
    return false unless seen.add?(type)
    return true if type.to_s == "String::Builder"
    if type.is_a?(GenericClassInstanceType)
      return false if type.to_s.starts_with?("Array::View(") ||
                      type.to_s.starts_with?("RisTree::View(") ||
                      type.to_s.starts_with?("SlicePool::Run(")
      return true if {"Array", "RisTree", "SlicePool"}.includes?(type.generic_type.name)
    end
    case type
    when UnionType
      type.union_types.any? { |t| growing?(t, seen) }
    when InstanceVarContainer
      type.struct? && type.instance_vars.each_value.any? do |field|
        field.type?.try { |t| growing?(t, seen) } == true
      end
    else
      false
    end
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
    check_initializers(@program)
    @program.file_modules.each_value { |type| check_initializers(type) }
    @graph.defs.each_value { |target| reach(target) }
    node.accept Finder.new(self)
    @program.const_initializers.each { |i| i.value.accept Finder.new(self, initial: i.value) }
    @program.class_var_initializers.each { |i| i.node.accept Finder.new(self, initial: i.node) }
  end

  private def check_initializers(type : Type)
    if type.responds_to?(:instance_vars_initializers)
      type.instance_vars_initializers.try &.each do |initializer|
        initializer.value.accept Finder.new(self)
      end
    end
    type.types?.try &.each_value { |nested| check_initializers(nested) }
    if type.is_a?(GenericType)
      type.each_instantiated_type { |instance| check_initializers(instance) }
    end
  end

  def owner?(node : ASTNode) : Bool
    node.type?.try { |t| TapeOwnerChecker.owner?(@program, t) } == true
  end

  def reach(target : Def) : Nil
    return if target.body.is_a?(Primitive)
    return if @graph.opaque?(target)
    return unless @seen.add?(target.object_id)
    # The compiler's generated constructor returns its fresh receiver.
    if target.name == "new" && target.type?.try { |t| TapeOwnerChecker.owner?(@program, t) }
      return
    end
    finder = Finder.new(self, target)
    target.body.accept finder
    finder.finish
  end

  def refuse(node : ASTNode, why : String) : NoReturn
    node.raise "#{why}; borrow it: pass the owner variable. " \
               "Declare one owner per scope"
  end

  class Finder < Visitor
    @allowed = Set(UInt64).new
    @bindings = Set(String).new
    @locals = Set(String).new

    def initialize(@checker : TapeOwnerChecker, @def : Def? = nil,
                   initial : ASTNode? = nil)
      @allowed << initial.object_id if initial
      @def.try do |d|
        d.args.each { |a| @bindings << a.name }
      end
    end

    def finish
      return unless d = @def
      return if TapeScopeChecker.constructor?(d)
      return unless d.type?.try { |t| TapeOwnerChecker.owner_in(@checker.program, t) }
      body = TapeScopeChecker.parts(d.body).try(&.[1]) || d.body
      refuse_return(body) if local_owner?(body)
    end

    def visit_any(node)
      return true if node.is_a?(Def)
      # Probes use fake values solely to instantiate the user's defs.
      # Check those bodies, not the probe's temporary union result.
      if node.is_a?(If) && node.iyi_definition_probe?
        return false
      end
      true
    end

    def visit(node : Assign)
      bind(node, node.target, node.value)
      false
    end

    def visit(node : TypeDeclaration)
      if value = node.value
        bind(node, node.var, value)
      end
      false
    end

    private def bind(node, target, value)
      if value.is_a?(Call) && value.name == "new" && @checker.owner?(value)
        if target.is_a?(Var)
          unless @bindings.add?(target.name)
            @checker.refuse(node, "owner construction requires a named declaration")
          end
        elsif !target.is_a?(Path) && !target.is_a?(ClassVar)
          @checker.refuse(node, "owner construction requires a named declaration")
        end
        @allowed << value.object_id
        @locals << target.name if target.is_a?(Var)
      elsif target.is_a?(Var) && local_owner?(value)
        @locals << target.name
      end
      value.accept self
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      if node.name == "new" && @checker.owner?(node) && !@allowed.includes?(node.object_id)
        @checker.refuse(node, "owner temporary requires a named declaration")
      end
      if node.program_initializer?
        if block = node.block
          body = TapeScopeChecker.parts(block.body).try(&.[1]) || block.body
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

    private def owner_initialize? : Bool
      @def.try do |d|
        TapeScopeChecker.constructor?(d)
      end == true
    end

    private def local_owner?(node : ASTNode) : Bool
      case node
      when Expressions
        node.expressions.last?.try { |last| local_owner?(last) } == true
      when Var
        @checker.owner?(node) && @locals.includes?(node.name)
      when Call
        node.name == "new" && @checker.owner?(node)
      when If
        local_owner?(node.then) || local_owner?(node.else)
      else
        false
      end
    end

    private def refuse_return(node : ASTNode) : NoReturn
      node.raise "cannot return an owner from a def; " \
                 "def #{@def.try(&.name)} must " \
                 "copy_to(owner), return a field view (String/Array) or " \
                 "take the owner as an argument"
    end

    def visit(node : Return)
      if (exp = node.exp) && (d = @def) && !owner_initialize? &&
         d.type?.try { |t| TapeOwnerChecker.owner_in(@checker.program, t) }
        refuse_return(node) if local_owner?(exp)
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
