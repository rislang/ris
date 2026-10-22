# ris: Goose frees every scope's data when the scope ends. Here a def's
# body, a `while` body or a block body (not the prelude's) frees what it
# put on the tape at its end, each round, when nothing it made can
# outlive it; a `return` or `break` past the end frees nothing. The normalizer writes the body as
#
#   __mark = __iyi_scope_mark(false)
#   __value = (body)
#   __iyi_scope_reset(__mark)
#   __value
#
# and this checker, once types are known, turns the `false` to `true`
# where it proves the body keeps nothing: its value (a def's result) is
# no tape value, no raw pointer or IyiRegion is in it, nothing in the body yields, a variable of the code around it is
# not assigned a tape value, and a tape value from outside the body - a
# variable around it, a block parameter - is only a `Tape::String` or
# read (`[]`, `size`, `each`, ...), never grown, written or passed on.
# A tape variable of the body's own is assigned first at the body's top
# level and used nowhere else. Any doubt leaves the mark off: the tape
# then frees the body's values with the scope, as before.
class Iyi::TapeScopeChecker
  MARK  = "__iyi_scope_mark"
  RESET = "__iyi_scope_reset"
  READS = {"[]", "[]?", "size", "bytesize", "length", "empty?", "each",
           "each_byte", "each_with_index", "each_child", "stop", "==",
           "!=", "starts_with?", "finish", "none?", "index", "start",
           "map", "sum", "__loop_fetch", "bytes"}

  def self.declares?(body : ASTNode) : Bool
    nodes = body.is_a?(Expressions) ? body.expressions : [body]
    nodes.any? do |node|
      node.is_a?(Def) || node.is_a?(ClassDef) || node.is_a?(ModuleDef) ||
        node.is_a?(Macro) || node.is_a?(EnumDef) || node.is_a?(Alias) ||
        node.is_a?(Include) || node.is_a?(Extend) || node.is_a?(VisibilityModifier) ||
        node.is_a?(Annotation)
    end
  end

  def self.mark(program : Program, node : While | Block | Def) : Nil
    return if !program.tape_scopes? || !program.tape_platform? ||
              TapeScopeRuntime.runtime?(node.location) ||
              TapeScopeRuntime.prelude?(program, node.location)
    body = node.body
    return if body.is_a?(Nop) || body.is_a?(Primitive)
    # A getter's field, `self` or a literal puts nothing on the tape, and a
    # struct's getter and `self` answer the value in place only unwrapped.
    return if body.is_a?(InstanceVar) || body.is_a?(Var) ||
              body.is_a?(ClassVar) || body.is_a?(Path) ||
              body.is_a?(NumberLiteral) || body.is_a?(BoolLiteral) ||
              body.is_a?(NilLiteral) || body.is_a?(SymbolLiteral) ||
              body.is_a?(CharLiteral) || body.is_a?(StringLiteral)
    # A body read from an artifact is marked already, with its build's
    # temporaries: a second mark's fresh ones could share their names.
    return if parts(body)
    return if node.is_a?(Def) && (node.abstract? || node.name == "initialize")
    # A block that declares methods or types is a macro's body (`record
    # ... do def ... end end`), not code that runs: wrapping it would put
    # the declarations inside an expression.
    return if node.is_a?(Block) && declares?(body)
    on = BoolLiteral.new(false).at(body)
    # Named by the body's file: an artifact's def keeps its build's names,
    # and a consumer's block inlined into it must not take them again.
    mark = program.new_temp_var(node).at(body)
    value = program.new_temp_var(node).at(body)
    node.body = Expressions.new([
      Assign.new(mark, Call.new(nil, MARK, on, global: true).at(body)).at(body),
      Assign.new(value, body).at(body),
      Call.new(nil, RESET, mark.clone, global: true).at(body),
      value.clone,
    ] of ASTNode).at(body)
  end

  # The pieces of a marked body: the flag and the body as written.
  def self.parts(node : ASTNode) : {BoolLiteral, ASTNode}?
    return nil unless node.is_a?(Expressions) && node.expressions.size == 4
    first, second = node.expressions[0], node.expressions[1]
    return nil unless first.is_a?(Assign) && second.is_a?(Assign)
    call = first.value
    return nil unless call.is_a?(Call) && call.name == MARK
    flag = call.args.first?
    return nil unless flag.is_a?(BoolLiteral)
    {flag, second.value}
  end

  def initialize(@program : Program)
  end

  @seen = Set(UInt64).new
  @decided = [] of Expressions

  def run(node : ASTNode) : Nil
    check_scope(node, false)
    # A loop's or block's mark left off frees nothing, but its two calls
    # still run each round in an unoptimised build: the body is left as
    # it was written. A def's runs once a call and stays: unwrapped, a
    # yielding def inlined into its caller clobbered the caller's index.
    @decided.each do |wrapper|
      next unless parts = TapeScopeChecker.parts(wrapper)
      flag, inner = parts
      wrapper.expressions = [inner] of ASTNode unless flag.value
    end
  end

  def decide(body : ASTNode, flag : BoolLiteral, value : Bool) : Nil
    flag.value = value
    @decided << body if body.is_a?(Expressions)
  end

  def reach(a_def : Def) : Nil
    return unless @seen.add?(a_def.object_id)
    owner_tape = a_def.owner.try { |owner| TapeChecker.tape?(@program, owner) } || false
    params = a_def.args.map(&.name)
    a_def.block_arg.try { |arg| params << arg.name }
    check_scope(a_def.body, owner_tape, params)
    # The def's own scope: what it made, unless it is the result.
    if parts = TapeScopeChecker.parts(a_def.body)
      flag, inner = parts
      flag.value = allocates?(inner) &&
                   safe?(inner, a_def.type?, a_def.body, owner_tape, params, [] of String)
    end
  end

  # Whether *node* can put anything on the tape: every tape allocation goes
  # through one of `IyiRegion`'s TAKES, so a body that reaches none of them
  # through any call it makes
  # (`h = (h ^ c) &* p`, a getter, `UInt64#<<`) puts nothing there, and its
  # mark would only cost each round. A def being looked at counts as not
  # allocating while it is: its other calls decide. Past DEPTH calls down
  # the answer is yes, as any doubt is.
  DEPTH = 16
  TAKES = {"tape_bytes", "tape_resize", "take", "grow_onto", "tape_scope", "tape_local", "tape="}
  @allocates = {} of UInt64 => Bool
  @depth = 0

  def allocates?(node : ASTNode) : Bool
    finder = AllocFinder.new(self)
    node.accept(finder)
    finder.found
  end

  def def_allocates?(a_def : Def) : Bool
    return @allocates[a_def.object_id] if @allocates.has_key?(a_def.object_id)
    body = a_def.body
    return false if body.is_a?(Primitive)
    return true if @depth >= DEPTH
    @allocates[a_def.object_id] = false
    @depth += 1
    result = allocates?(body)
    @depth -= 1
    # A no found under the depth limit may lean on a def still being
    # looked at; only a yes, or a no at the top, is kept.
    if result || @depth == 0
      @allocates[a_def.object_id] = result
    else
      @allocates.delete(a_def.object_id)
    end
    result
  end

  class AllocFinder < Visitor
    getter found = false

    def initialize(@checker : TapeScopeChecker)
    end

    # A call that never returns (`raise`, `abort`) leaves by unwinding,
    # which releases the tape past the mark anyway: what its message puts
    # there does not count.
    def visit(node : Call)
      return false if @found
      return false if node.type?.try(&.no_return?)
      # The marks themselves only read the tape's cursor.
      return false if node.name == MARK || node.name == RESET
      obj = node.obj
      # The GC heap and its collector never take tape.
      return false if obj.is_a?(Path) && {"IyiHeap", "IyiMark"}.includes?(obj.names.last?)
      if obj.is_a?(Path) && obj.names.last? == "IyiRegion" && TAKES.includes?(node.name)
        @found = true
        return false
      end
      if defs = node.target_defs
        @found = true if defs.any? { |a_def| @checker.def_allocates?(a_def) }
      end
      node.expanded.try &.accept(self)
      !@found
    end

    def visit(node : ASTNode)
      !@found
    end
  end

  private def check_scope(scope : ASTNode, owner_tape : Bool, params = [] of String) : Nil
    scope.accept(Finder.new(self, scope, owner_tape, params))
  end

  def tape?(type : Type?) : Bool
    !type.nil? && !TapeChecker.tape_in(@program, type).nil?
  end

  def tape_string?(type : Type?) : Bool
    !type.nil? && type.remove_typedef.to_s == "Tape::String"
  end

  # Whether *body*, inside *scope*, keeps nothing it puts on the tape.
  def safe?(body : ASTNode, value_type : Type?, scope : ASTNode, owner_tape : Bool,
            params : Array(String), block_args : Array(String)) : Bool
    return false if owner_tape
    return false if tape?(value_type)
    outside = Hash(String, Int32).new(0)
    scope.accept(Counter.new(outside))
    inside = Hash(String, Int32).new(0)
    body.accept(Counter.new(inside))
    inner = Set(String).new
    if body.is_a?(Expressions)
      statements = body.expressions
    else
      statements = [body]
    end
    seen = Set(String).new
    statements.each do |statement|
      if statement.is_a?(Assign) && (target = statement.target).is_a?(Var)
        name = target.name
        if !seen.includes?(name) && outside[name] == inside[name] &&
           !params.includes?(name) && !block_args.includes?(name) &&
           !Counter.mentions?(statement.value, name)
          inner << name
        end
      end
      statement.accept(Counter.new(Hash(String, Int32).new(0)).tap { |c| c.names = seen })
    end
    scan = Scan.new(self, inner)
    body.accept(scan)
    scan.safe
  end

  # Counts the uses of each variable name.
  class Counter < Visitor
    property names : Set(String)? = nil

    def initialize(@counts : Hash(String, Int32))
    end

    def self.mentions?(node : ASTNode, name : String) : Bool
      counts = Hash(String, Int32).new(0)
      node.accept(new(counts))
      counts[name] > 0
    end

    def visit(node : Var)
      @counts[node.name] += 1
      @names.try(&.<<(node.name))
      false
    end

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end

  class Scan < Visitor
    getter safe = true

    def initialize(@checker : TapeScopeChecker, @inner : Set(String))
    end

    def outer_tape?(node : ASTNode) : Bool
      node.is_a?(Var) && !@inner.includes?(node.name) && @checker.tape?(node.type?) &&
        !@checker.tape_string?(node.type?)
    end

    def visit(node : Yield)
      @safe = false
      false
    end

    def visit(node : Assign)
      target = node.target
      if target.is_a?(Var)
        @safe = false if !@inner.includes?(target.name) && @checker.tape?(node.value.type?)
      elsif @checker.tape?(node.value.type?)
        @safe = false
      end
      node.value.accept(self)
      false
    end

    def visit(node : OpAssign | MultiAssign | InstanceVar | ClassVar | Global)
      @safe = false
      false
    end

    # A read of a tape value from outside is kept only when what it gives
    # is no tape value, or text: `outer[0]` may be a writer of the outer
    # scope's, which the body would then grow.
    def visit(node : Call)
      @safe = false if pointer?(node) || node.name == "to_unsafe"
      obj = node.obj
      outer = !obj.nil? && outer_tape?(obj)
      if obj && outer
        ok = READS.includes?(node.name) &&
             (!@checker.tape?(node.type?) || @checker.tape_string?(node.type?))
        @safe = false unless ok
      else
        obj.try &.accept(self)
      end
      node.args.each &.accept(self)
      node.named_args.try &.each &.value.accept(self)
      if block = node.block
        # A call given only the body's own values yields only those, or
        # what it makes (`Tape::String.build { |w| ... }`): its block's
        # parameters are the body's own too.
        # A block's parameters shadow the names around it, so they are its
        # own only while it is read.
        saved = @inner
        unless outer
          @inner = @inner.dup
          block.args.each { |arg| @inner << arg.name }
        end
        block.accept(self)
        @inner = saved
      end
      false
    end

    # The library reaches into the tape with raw pointers, which this scan
    # cannot follow: a body holding one keeps its tape.
    def pointer?(node : ASTNode) : Bool
      type = node.type?
      !type.nil? && type.remove_typedef.is_a?(PointerInstanceType)
    end

    def visit(node : Path)
      @safe = false if node.names.last? == "IyiRegion" || node.names.last? == "IyiHeap"
      false
    end

    # A tape value from outside, anywhere but a read's receiver.
    def visit(node : Var)
      @safe = false if pointer?(node)
      @safe = false if outer_tape?(node)
      false
    end

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end

  class Finder < Visitor
    def initialize(@checker : TapeScopeChecker, @scope : ASTNode, @owner_tape : Bool,
                   @params : Array(String))
    end

    def visit(node : Call)
      node.target_defs.try &.each { |a_def| @checker.reach(a_def) }
      if expanded = node.expanded
        expanded.accept self
      end
      true
    end

    def visit(node : While)
      check(node.body, nil, [] of String)
      true
    end

    def visit(node : Block)
      check(node.body, node.body.type?, node.args.map(&.name))
      true
    end

    private def check(body : ASTNode, value_type : Type?, block_args : Array(String)) : Nil
      parts = TapeScopeChecker.parts(body)
      return unless parts
      flag, inner = parts
      # A body that puts nothing on the tape keeps its wrapper with the
      # mark off: the off mark folds to nothing in a release build.
      unless @checker.allocates?(inner)
        flag.value = false
        return
      end
      @checker.decide(body, flag, @checker.safe?(inner, value_type, @scope, @owner_tape, @params, block_args))
    end

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end
end

# Where the tape's own runtime is: the prelude and the compiler's code,
# which is never marked, nor is Crystal's code (a `.cr` file), which has
# no tape: marking it wrapped the block of `record Value128 ... do def
# ... end end` in an expression, and its `def` could not be declared, so
# a compiler built from source could not build itself. `std/` is marked:
# its raw pointers keep a body's tape (`Scan#pointer?`), and it keeps no
# pointer into a tape in a heap object.
module Iyi::TapeScopeRuntime
  def self.runtime?(location : Location?) : Bool
    file = location.try(&.original_filename)
    return true unless file
    file = file.gsub('\\', '/')
    crystal?(location) || file.includes?("/src/iyi/") || file.includes?("/src/compiler/")
  end

  # The prelude where it was loaded from, which a test may copy out of
  # `src/iyi/` to change it.
  def self.prelude?(program : Program, location : Location?) : Bool
    return false unless directory = program.iyi_prelude_dir
    file = location.try(&.original_filename)
    return false unless file
    # Windows names the copy with backslashes; compare as `TapeRules.runtime?` does.
    file.gsub('\\', '/').starts_with?(directory.gsub('\\', '/').rstrip('/') + "/")
  end

  # Crystal's code, a `.cr` file: none of the tape's lowerings apply to it,
  # as it has no tape and no `__loop_fetch`.
  def self.crystal?(location : Location?) : Bool
    file = location.try(&.original_filename)
    !file.nil? && file.ends_with?(".cr")
  end
end

# Where ris's own code ends, for the lowerings that stay out of `std/`.
module Iyi::TapePointerCheckerLibrary
  def self.library?(location : Location?) : Bool
    file = location.try(&.original_filename)
    return true unless file
    file = file.gsub('\\', '/')
    file.includes?("/std/") || file.includes?("/src/iyi/") ||
      file.includes?("/src/compiler/") || file.ends_with?(".cr")
  end
end
