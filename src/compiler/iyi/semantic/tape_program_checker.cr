# Program storage is the outermost root. Track its provenance through calls
# and aliases; an unknown result is request-owned. This is deliberately
# conservative until general owner roots (step 3) exist.
class Iyi::TapeProgramChecker
  # Abstract storage identities preserve aliases, including references held
  # in request structs/arrays that themselves refer to program containers.
  class Origin
    getter kind : Symbol
    getter fields = {} of String => Origin
    property element : Origin?

    def initialize(@kind)
    end

    def program? : Bool
      @kind == :program || @kind == :scalar
    end

    def request? : Bool
      @kind == :request || @kind == :local
    end

    Scalar  = Origin.new(:scalar)
    Program = Origin.new(:program)
    Unknown = Origin.new(:unknown)
  end

  alias Env = Hash(String, Origin)
  READ_VIEWS = {"[]", "[]?", "first", "first?", "last", "last?", "fetch",
                "finish", "as_tape", "view", "unchecked", "__loop_fetch",
                "find", "max_by", "min_by", "pop", "pop?", "string",
                "rest", "peek", "scan", "check", "scan_until", "check_until"}
  YIELDS_VIEWS = {"each", "each_with_index", "each_child", "each_line",
                  "find", "map", "select", "reject", "reduce", "max_by",
                  "min_by", "count", "any?", "all?", "sort_in_place",
                  "sort_in_place_by"}
  WRITES = {"<<", "push", "[]=", "__loop_store", "unchecked_store", "clear",
            "pop", "pop?", "shift", "truncate", "reserve", "append", "put",
            "leaf", "open", "close", "write_bytes", "append_bytes",
            "sort_in_place", "sort_in_place_by", "load", "concat",
            "write_bytes_at", "offset=", "advance", "reset", "terminate",
            "scan", "skip", "scan_until", "skip_until"}

  @active = Set(UInt64).new
  @joining = Set({UInt64, UInt64}).new
  @globals = {} of UInt64 => Bool
  @program_context = false
  @self_safe : Origin = Origin::Unknown
  @self_tape = false
  @returned : Origin? = nil

  class Binding
    getter block : Block, env : Env, program : Bool, origin : Origin, tape : Bool
    getter parent : Binding?

    def initialize(@block, @env, @program, @origin, @parent, @tape)
    end
  end

  @binding : Binding?
  @has_threads = false
  @mutations = [] of ASTNode

  getter graph : TapeCallGraph

  def initialize(@program : Program, @graph : TapeCallGraph)
  end

  def tape?(node : ASTNode) : Bool
    !!node.type?.try { |type| TapeChecker.tape_in(@program, type) }
  end

  def run(node : ASTNode) : Nil
    @program.const_initializers.each { |init| initializer(init.value) }
    @program.class_var_initializers.each { |init| initializer(init.node) }
    roots = @program.const_initializers.any? { |init| tape?(init.value) } ||
            @program.class_var_initializers.any? do |init|
              init.owner.class_vars[init.name]?.try(&.type?).try do |type|
                TapeChecker.tape_in(@program, type)
              end
            end
    unless roots
      use = ProgramUse.new(@program, @graph)
      node.accept(use)
      return unless use.found
    end
    value(node, Env.new)
    if @has_threads && (write = @mutations.first?)
      write.raise "program tape writes require a single kernel thread;\n" \
                  "initialize state before starting threads and only read it"
    end
  end

  private def initializer(node : ASTNode)
    return if TapeRules.runtime?(@program, node.location)
    saved = @program_context
    @program_context = false
    result = value(node, Env.new)
    refuse(node) if tape?(node) && !result.program?
    @program_context = saved
  end

  private def refuse(node : ASTNode)
    node.raise "cannot store request tape data on the program tape;\n" \
               "copy it with .copy_to(Program.tape)"
  end

  private def mutation(node : ASTNode)
    @mutations << node unless @program_context
  end

  private def active_origin : Origin
    Origin.new(@program_context ? :program : :request)
  end

  private def join(a : Origin, b : Origin) : Origin
    return b if a.kind == :scalar
    return a if b.kind == :scalar || a.same?(b)
    return Origin::Unknown unless a.kind == b.kind
    return a unless a.request?
    key = {a.object_id, b.object_id}
    return Origin::Unknown unless @joining.add?(key)
    b.fields.each do |name, origin|
      a.fields[name] = a.fields[name]?.try { |old| join(old, origin) } || origin
    end
    if element = b.element
      a.element = a.element.try { |old| join(old, element) } || element
    end
    @joining.delete(key)
    a
  end

  private def viewed(origin : Origin) : Origin
    return origin if origin.kind == :local
    origin.program? ? Origin::Program : Origin::Unknown
  end

  def value(node : ASTNode, env : Env) : Origin
    safe = case node
           when Expressions
             result = Origin::Program
             node.expressions.each { |exp| result = value(exp, env) }
             result
           when Var
             env[node.name]? || Origin::Unknown
           when Self
             @self_safe
           when InstanceVar
             @self_safe.fields[node.name]? || viewed(@self_safe)
           when ClassVar, Global, Path, StringLiteral
             Origin::Program
           when Assign
             if node.target.is_a?(Path) ||
                (node.target.is_a?(ClassVar) && !node.target.type?)
               return Origin::Program # Declaration, initialized separately.
             end
             result = value(node.value, env)
             case target = node.target
             when Var
               env[target.name] = result
             when ClassVar, Global
               if tape?(node.value)
                 refuse(node) unless result.program?
                 mutation(node)
               end
             when InstanceVar
               @self_safe.fields[target.name] = @self_safe.fields[target.name]?.try do |old|
                 join(old, result)
               end || result
               if @self_tape && program_target?(@self_safe, node)
                 refuse(node) if tape?(node.value) && !result.program?
                 mutation(node)
               end
             end
             result
           when TypeDeclaration
             return Origin::Program if node.var.is_a?(ClassVar) || node.var.is_a?(Path)
             if exp = node.value
               result = value(exp, env)
               env[node.var.as(Var).name] = result if node.var.is_a?(Var)
               result
             else
               Origin::Program
             end
           when Call
             call(node, env)
           when If
             value(node.cond, env)
             left, right = env.dup, env.dup
             a, b = value(node.then, left), value(node.else, right)
             (left.keys | right.keys).each do |name|
               env[name] = join(left[name]? || Origin::Unknown,
                 right[name]? || Origin::Unknown)
             end
             join(a, b)
           when While
             loop do
               previous = env.dup
               value(node.cond, env)
               value(node.body, env)
               previous.each do |name, origin|
                 env[name] = join(origin, env[name]? || Origin::Unknown)
               end
               break if env == previous
             end
             Origin::Program
           when Return
             result = node.exp.try { |exp| value(exp, env) } || Origin::Program
             @returned = @returned.try { |old| join(old, result) } || result
             result
           when Cast
             value(node.obj, env)
           when Primitive
             node.name == "allocate" ? active_origin : Origin::Unknown
           when ProcLiteral
             previous = @program_context
             @program_context = false
             reach(node.def, Array(Origin).new, Origin::Unknown, nil)
             @program_context = previous
             Origin::Program
           when Yield
             args = node.exps.map { |exp| value(exp, env) }
             if binding = @binding
               block, outer = binding.block, binding.env
               saved_program, saved_self = @program_context, @self_safe
               saved_binding, saved_tape = @binding, @self_tape
               @binding, @self_tape = binding.parent, binding.tape
               @program_context, @self_safe = binding.program, binding.origin
               block.args.each_with_index { |arg, i| outer[arg.name] = args[i]? || Origin::Unknown }
               result = value(block.body, outer)
               @program_context, @self_safe = saved_program, saved_self
               @binding, @self_tape = saved_binding, saved_tape
               result
             else
               Origin::Unknown
             end
           when Def, FunDef, ClassDef, ModuleDef, Macro
             Origin::Program
           else
             node.accept Children.new(self, env, node)
             Origin::Unknown
           end
    tape?(node) ? safe : Origin::Scalar
  end

  private def call(node : Call, env : Env) : Origin
    if expanded = node.expanded
      return value(expanded, env)
    end
    receiver = (obj = node.obj) ? value(obj, env) : @self_safe
    args = node.args.map { |arg| value(arg, env) }
    node.named_args.try &.each { |arg| value(arg.value, env) }
    node.block_arg.try { |arg| value(arg, env) }
    targets = @graph.targets(node)
    return Origin::Unknown unless targets
    result : Origin? = nil
    targets.each do |target|
      runtime = TapeRules.runtime?(@program, target.location)
      if runtime && node.name == "__ris_program_init"
        node.raise "program initializer is private; use .copy_to(Program.tape)" unless node.program_initializer?
        if block = node.block
          saved = @program_context
          @program_context = true
          result = value(block.body, env)
          @program_context = saved
        end
      elsif runtime && node.name == "copy_to"
        mutation(node)
        result = node.args.first?.try(&.type?.try(&.to_s)) == "Program::TapeOwner" ? Origin::Program : Origin::Unknown
      elsif runtime && ((target.owner.to_s == "Program::TapeOwner" && node.name == "run") ||
            (target.owner.to_s == "RisRegion.class" &&
            (node.name.starts_with?("program_") || node.name == "release_program")))
        unless TapeRules.runtime?(@program, node.location)
          node.raise "Program.tape.run is private; use .copy_to(Program.tape)"
        end
      elsif runtime
        threaded = @graph.threaded?(target)
        @has_threads = true if threaded
        if @program_context && @graph.suspends?(node)
          node.raise "program tape initializers cannot suspend; initialize before spawning fibers"
        end
        tape_receiver = node.obj.try { |obj| tape?(obj) } ||
                        TapeChecker.tape?(@program, target.owner)
        writes = WRITES.includes?(node.name) || node.name.starts_with?("append_")
        if tape_receiver && {"push", "<<", "[]=", "__loop_store", "unchecked_store", "leaf", "open", "put"}.includes?(node.name)
          if stored = args.last?
            receiver.element = receiver.element.try { |old| join(old, stored) } || stored
          end
        end
        if tape_receiver && program_target?(receiver, node) && writes
          node.args.each_with_index do |arg, i|
            copies_bytes = target.owner.to_s == "String::Builder" ||
                           (target.owner.to_s == "Array(UInt8)" && node.name == "append")
            refuse(arg) if tape?(arg) && !args[i].program? && !copies_bytes
          end
          mutation(node)
        end
        yielded : Origin? = nil
        if block = node.block
          outer = env.dup
          block.args.each do |arg|
            outer[arg.name] = YIELDS_VIEWS.includes?(node.name) ? (receiver.element || viewed(receiver)) : active_origin
          end
          saved = @program_context
          @program_context = false if node.name == "local_tape"
          loop do
            before = env.dup
            yielded = value(block.body, outer)
            env.each do |name, origin|
              next if block.args.any? { |arg| arg.name == name }
              merged = join(origin, outer[name]? || Origin::Unknown)
              env[name] = outer[name] = merged
            end
            break if env == before
          end
          @program_context = saved
        end
        origin = if node.name == "view" && target.owner.to_s == "String.class"
                   Origin::Program
                 elsif READ_VIEWS.includes?(node.name) && tape_receiver
                   receiver.element || viewed(receiver)
                 elsif {"<<", "concat"}.includes?(node.name) && tape_receiver
                   receiver
                 else
                   made = active_origin
                   if tape_receiver
                     made.element = receiver.element
                   elsif node.name == "new"
                     made.element = yielded
                   end
                   made
                 end
        result = result.try { |old| join(old, origin) } || origin
      else
        binding = node.block.try { |block| Binding.new(block, env, @program_context, @self_safe, @binding, @self_tape) }
        reached = reach(target, args, receiver, binding)
        result = result.try { |old| join(old, reached) } || reached
      end
    end
    tape?(node) ? (result || Origin::Unknown) : Origin::Scalar
  end

  private def reach(target : Def, args : Array(Origin), receiver : Origin,
                    binding : Binding?) : Origin
    return Origin::Unknown if @graph.opaque?(target)
    unless @program_context
      inputs = [receiver] + args
      # Library code names no program root of a .ri file: it reaches one
      # only through an input that is surely program storage.
      unless user?(target)
        if inputs.none? { |origin| contains_program?(origin, definite: true) } &&
           (!binding || binding.env.values.none? do |origin|
             contains_program?(origin, definite: true)
           end)
          return Origin.new(:local)
        end
      end
      if inputs.none? { |origin| contains_program?(origin) } &&
         !touches_program?(target) &&
         (!binding || binding.env.values.none? { |origin| contains_program?(origin) })
        if binding
          placeholders = binding.block.args.map { Origin.new(:local) }
          saved_self, saved_tape = @self_safe, @self_tape
          saved_binding, saved_program = @binding, @program_context
          @self_safe, @self_tape = binding.origin, binding.tape
          @binding, @program_context = binding.parent, binding.program
          placeholders.each_with_index do |origin, i|
            binding.env[binding.block.args[i].name] = origin
          end
          yielded = value(binding.block.body, binding.env)
          @self_safe, @self_tape = saved_self, saved_tape
          @binding, @program_context = saved_binding, saved_program
          if !contains_program?(yielded) &&
             binding.env.values.none? { |origin| contains_program?(origin) } &&
             (inputs + placeholders).none? { |origin| contains_program?(origin) }
            return Origin.new(:local)
          end
        else
          return Origin.new(:local)
        end
      end
    end
    return Origin::Unknown unless @active.add?(target.object_id)
    previous_self, previous_return, previous_binding = @self_safe, @returned, @binding
    previous_tape = @self_tape
    @self_tape = target.owner?.try { |owner| TapeChecker.tape?(@program, owner) } || false
    @self_safe, @returned, @binding = receiver, nil, binding
    env = Env.new
    target.args.each_with_index { |arg, i| env[arg.name] = args[i]? || Origin::Unknown }
    result = value(target.body, env)
    if returned = @returned
      result = join(result, returned)
    end
    @self_safe, @returned, @binding = previous_self, previous_return, previous_binding
    @self_tape = previous_tape
    @active.delete(target.object_id)
    result
  end

  private def contains_program?(origin : Origin, seen = Set(UInt64).new,
                                definite = false) : Bool
    return false unless seen.add?(origin.object_id)
    return true if origin.kind == :program
    return true if origin.kind == :unknown && !definite
    origin.fields.any? { |_, field| contains_program?(field, seen, definite) } ||
      origin.element.try { |element| contains_program?(element, seen, definite) } ||
      false
  end

  # Whether a write at *node* may land in program storage. In a .ri file
  # an unknown origin may be an alias of a root; library code holds one
  # only when handed it, so there it must be program storage itself: a
  # request value that merely refers to program data is no such target.
  private def program_target?(origin : Origin, node : ASTNode) : Bool
    return false if origin.request?
    file = node.location.try(&.original_filename)
    return true if file && file.ends_with?(".ri") &&
                   !TapeRules.std?(node.location)
    origin.kind == :program
  end

  private def user?(target : Def) : Bool
    file = target.location.try(&.original_filename)
    !!file && file.ends_with?(".ri") && !TapeRules.std?(target.location)
  end

  private def touches_program?(target : Def) : Bool
    @globals.fetch(target.object_id) do
      finder = GlobalUse.new(@program, @graph)
      target.body.accept(finder)
      @globals[target.object_id] = finder.found
    end
  end

  # A method with only isolated request inputs and no path to a program
  # root cannot affect program storage. Its result is isolated too. This
  # keeps the analysis proportional to code that can actually share state.
  class GlobalUse < Visitor
    getter found = false
    @seen = Set(UInt64).new

    def initialize(@program : Program, @graph : TapeCallGraph)
    end

    def visit(node : ClassVar)
      @found = true if node.type?.try do |type|
                         TapeChecker.tape_in(@program, type)
                       end
      false
    end

    # A type name such as `Str` is no storage; only a constant is.
    def visit(node : Path)
      @found = true if node.target_const &&
                       node.type?.try do |type|
                         TapeChecker.tape_in(@program, type)
                       end
      false
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      threaded = @graph.targets(node).try &.any? do |target|
        @graph.threaded?(target)
      end
      owner_api = @graph.targets(node).try &.any? do |target|
        target.owner.to_s == "Program::TapeOwner"
      end
      if threaded || owner_api || node.name == "copy_to" ||
         node.name == "__ris_program_init" || node.name == "release_program" ||
         node.name.starts_with?("program_")
        @found = true
      end
      @graph.targets(node).try &.each do |target|
        next if @graph.opaque?(target)
        target.body.accept(self) if @seen.add?(target.object_id)
      end
      true
    end

    def visit(node : ProcLiteral)
      unless @graph.opaque?(node.def)
        node.def.body.accept(self) if @seen.add?(node.def.object_id)
      end
      false
    end

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end

  # No program storage means no program-store question. Avoid interpreting
  # parsers and other large call graphs when all their data is request-owned.
  class ProgramUse < Visitor
    getter found = false
    @seen = Set(UInt64).new

    def initialize(@program : Program, @graph : TapeCallGraph)
    end

    # A class variable declared with a nil initializer (`@@r : R? = nil`)
    # is no initializer root, yet a later store makes it one.
    def visit(node : ClassVar)
      @found = true if node.type?.try do |type|
                         TapeChecker.tape_in(@program, type)
                       end
      false
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      if node.name == "copy_to" ||
         (node.name == "__ris_program_init" && !node.program_initializer?) ||
         @graph.targets(node).try(&.any? { |target| target.owner.to_s == "Program::TapeOwner" })
        @found = true
      end
      @graph.targets(node).try &.each do |target|
        next if @graph.opaque?(target)
        target.body.accept(self) if @seen.add?(target.object_id)
      end
      true
    end

    def visit(node : ProcLiteral)
      unless @graph.opaque?(node.def)
        node.def.body.accept(self) if @seen.add?(node.def.object_id)
      end
      false
    end

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end

  class Children < Visitor
    def initialize(@checker : TapeProgramChecker, @env : Env, @root : ASTNode)
    end

    def visit(node : ASTNode)
      return true if node.same?(@root)
      @checker.value(node, @env)
      false
    end
  end
end
