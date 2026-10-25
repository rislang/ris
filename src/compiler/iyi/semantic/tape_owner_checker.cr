# Owners have one named binding; codegen borrows ordinary def arguments.
# Construction may copy a private temporary; initialize must not publish it.
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
    if target.name == "initialize" && TapeOwnerChecker.owner?(@program, target.owner)
      target.body.accept Initialization.new(self, target.owner)
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

  # Unoptimized LLVM builds new's temporary, then copies its header into
  # the local/constant slot (owners.ri checks both addresses). Keep that
  # temporary private, including through aliases and receiver helpers.
  class Initialization < Visitor
    @aliases = Set(String).new
    @seen = Hash(UInt64, Int32).new

    def initialize(@checker : TapeOwnerChecker, @owner : Type)
    end

    def rooted?(node : ASTNode) : Bool
      roots = Roots.new(@aliases, @owner)
      node.accept roots
      roots.found
    end

    class Roots < Visitor
      getter found = false

      def initialize(@aliases : Set(String), @owner : Type)
      end

      def visit(node : Var)
        @found ||= node.name == "self" || @aliases.includes?(node.name)
        false
      end

      def visit(node : Call)
        @found ||= !node.obj &&
          node.target_defs.try(&.any? { |d| d.owner == @owner }) == true
        true
      end

      def visit(node : InstanceVar)
        @found = true
        false
      end

      def visit(node : ASTNode)
        true
      end
    end

    def visit(node : Assign)
      if node.target.is_a?(Var) && rooted?(node.value)
        @aliases << node.target.as(Var).name
      end
      true
    end

    def visit(node : TypeDeclaration)
      if (value = node.value) && node.var.is_a?(Var) && rooted?(value)
        @aliases << node.var.as(Var).name
      end
      true
    end

    def visit(node : Yield)
      if node.exps.any? { |e| view?(e) && rooted?(e) }
        node.raise "cannot publish self or a field view from an owner's " \
                   "initialize; call the owner's own methods until " \
                   "construction finishes"
      end
      true
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      own = node.target_defs.try &.all? { |d| d.owner == @owner }
      # A field's own methods (`@left << 1`) fill it in place; passing a
      # view on as an argument is what could publish the temporary.
      exposes = node.args.any? { |a| view?(a) && rooted?(a) }
      if exposes && !own
        node.raise "cannot publish self or a field view from an owner's " \
                   "initialize; call the owner's own methods until " \
                   "construction finishes"
      end
      if own
        node.target_defs.try &.each do |d|
          d.args.zip(node.args) do |arg, value|
            @aliases << arg.name if rooted?(value)
          end
          # Revisit when a later call gives a helper another rooted arg.
          next if @seen[d.object_id]? == @aliases.size
          @seen[d.object_id] = @aliases.size
          d.body.accept self
        end
      end
      true
    end

    private def view?(node : ASTNode) : Bool
      node.type?.try do |t|
        !!TapeChecker.tape_in(@checker.program, t) || t.is_a?(PointerInstanceType)
      end == true
    end

    def visit(node : Def | Macro)
      false
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
        if @checker.owner?(body) && !owner_initialize?
          refuse_return(body)
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
      node.target_defs.try &.each do |d|
        if node.args.any? { |a| @checker.owner?(a) } &&
           (d.is_a?(External) || d.body.is_a?(Primitive))
          @checker.refuse(node, "owner arguments require a direct def call")
        end
        @checker.reach(d)
      end
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

    private def owner_initialize? : Bool
      @def.try do |d|
        d.name == "initialize" &&
          TapeOwnerChecker.owner?(@checker.program, d.owner)
      end == true
    end

    private def refuse_return(node : ASTNode) : NoReturn
      node.raise "cannot return an owner from a def; " \
                 "return a field view (Str/Ary) or " \
                 "take the owner as an argument"
    end

    def visit(node : Return)
      if (exp = node.exp) && @def && !owner_initialize?
        refuse_return(node) if @checker.owner?(exp)
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
