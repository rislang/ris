# A scope mark records the caller's allocation boundary. Discarded results
# reset it directly. A def's retained result goes through RESULT instead:
# fresh storage is staged outside rollback, then copied to the restored
# caller boundary; borrowed storage is left as a view. The mark stays off
# unless this checker proves no other storage escapes through side effects.
class Iyi::TapeScopeChecker
  MARK   = "__iyi_scope_mark"
  RESET  = "__iyi_scope_reset"
  RESULT = "__iyi_scope_result"
  READS  = {"[]", "[]?", "size", "bytesize", "length", "empty?", "each",
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
    body = body.transform(Returns.new(mark)) if node.is_a?(Def)
    cleanup = if node.is_a?(Def)
                result = Call.new(nil, RESULT,
                  [mark.clone, value.clone] of ASTNode, global: true).at(body)
                Assign.new(value.clone, result).at(body)
              else
                Call.new(nil, RESET, mark.clone, global: true).at(body)
              end
    node.body = Expressions.new([
      Assign.new(mark, Call.new(nil, MARK, on, global: true).at(body)).at(body),
      Assign.new(value, body).at(body),
      cleanup,
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

  getter graph : TapeCallGraph

  # The explicit `tape` blocks TapeShrinkChecker walked and could prove:
  # it refuses storing their data anywhere that outlives them (TAPE_SPEC
  # 3.2) and saw no call grow or opaquely keep outer storage in them.
  @proved = Set(UInt64).new

  def initialize(@program : Program, @graph : TapeCallGraph,
                 walked = Set(UInt64).new, tainted = Set(UInt64).new)
    @proved = walked - tainted
  end

  def proved?(block : Block) : Bool
    @proved.includes?(block.object_id)
  end

  @seen = Set(UInt64).new
  @decided = [] of Expressions

  def run(node : ASTNode) : Nil
    @graph.defs.each_value { |target| reach(target) }
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
    owner_tape = a_def.owner?.try { |owner| TapeChecker.tape?(@program, owner) } || false
    params = a_def.args.map(&.name)
    a_def.block_arg.try { |arg| params << arg.name }
    check_scope(a_def.body, owner_tape, params)
    # Retain a supported result while reclaiming the def's other storage.
    if parts = TapeScopeChecker.parts(a_def.body)
      flag, inner = parts
      # Older artifacts end with RESET rather than result reception. They
      # must keep the old conservative decision for tape-valued returns.
      cleanup = a_def.body.as(Expressions).expressions[2]
      pending = cleanup.is_a?(Assign) && (call = cleanup.value).is_a?(Call) &&
                call.name == RESULT && pending_type?(a_def.type?)
      flag.value = allocates?(inner) &&
                   safe?(inner, pending ? nil : a_def.type?,
                     a_def.body, owner_tape, params, [] of String)
    end
  end

  # Only shapes whose copy preserves borrowed storage can be promoted.
  # Classes and raw/self-relative pointers retain the conservative path.
  def pending_type?(type : Type?, seen = Set(Type).new) : Bool
    return false unless type
    type = type.remove_typedef
    return false if type.is_a?(PointerInstanceType) || type.is_a?(ProcInstanceType)
    return true if type.to_s == "String" || type.to_s == "String::Builder"
    return false unless seen.add?(type)
    case type
    when UnionType
      type.union_types.all? { |member| pending_type?(member, seen.dup) }
    when TupleInstanceType
      type.tuple_types.all? { |member| pending_type?(member, seen.dup) }
    when NamedTupleInstanceType
      type.entries.all? { |entry| pending_type?(entry.type, seen.dup) }
    when GenericClassInstanceType
      if {"Array", "RisTree"}.includes?(type.generic_type.name)
        type.type_vars.values.all? do |var|
          var.is_a?(Var) && pending_type?(var.type?, seen.dup)
        end
      elsif type.struct?
        type.instance_vars.values.all? { |var| pending_type?(var.type?, seen.dup) }
      else
        !tape?(type)
      end
    when NonGenericClassType
      if type.struct?
        type.instance_vars.values.all? { |var| pending_type?(var.type?, seen.dup) }
      else
        !tape?(type)
      end
    else
      !tape?(type)
    end
  end

  # An explicit return must receive its result before the def's rollback,
  # just like its final expression. Nested defs own their own marks.
  class Returns < Transformer
    def initialize(@mark : Var)
    end

    def transform(node : Return)
      exp = node.exp || NilLiteral.new.at(node)
      node.exp = Call.new(nil, RESULT, [@mark.clone, exp] of ASTNode,
        global: true).at(node)
      node
    end

    def transform(node : Def)
      node
    end
  end

  # Allocation is solved once over the shared specialized graph.
  def allocates?(node : ASTNode) : Bool
    @graph.allocates?(node)
  end

  private def check_scope(scope : ASTNode, owner_tape : Bool, params = [] of String) : Nil
    scope.accept(Finder.new(self, scope, owner_tape, params))
  end

  def tape?(type : Type?) : Bool
    !type.nil? && !TapeChecker.tape_in(@program, type).nil?
  end

  def tape_string?(type : Type?) : Bool
    !type.nil? && type.remove_typedef.to_s == "String"
  end

  # Whether *body*, inside *scope*, keeps nothing it puts on the tape.
  def safe?(body : ASTNode, value_type : Type?, scope : ASTNode, owner_tape : Bool,
            params : Array(String), block_args : Array(String),
            proved = false) : Bool
    return false if owner_tape && !proved
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
    scan = Scan.new(self, inner, proved)
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

    # C-entry bodies have their own locals too. Counting prelude memset
    # made a caller's unrelated `words` look live outside its tape block.
    def visit(node : Def | FunDef)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end

  class Scan < Visitor
    getter safe = true

    # *proved*: an explicit `tape` block whose calls TapeShrinkChecker
    # proved keep and grow nothing from outside it, so an outer tape value
    # may be read or handed to a call.
    def initialize(@checker : TapeScopeChecker, @inner : Set(String),
                   @proved = false)
    end

    def outer_tape?(node : ASTNode) : Bool
      return false if @proved
      node.is_a?(Var) && !@inner.includes?(node.name) && @checker.tape?(node.type?) &&
        !@checker.tape_string?(node.type?)
    end

    # Explicit returns receive their value before enclosing cleanup runs.
    # Keep storage for cleanup that may still read it on those paths.
    def visit(node : ExceptionHandler)
      @safe = false
      false
    end

    def visit(node : Yield)
      @safe = false
      false
    end

    def visit(node : Assign)
      target = node.target
      # A lent growing local rebound to its own text after the call
      # (Normalizer#lend_text_arguments) stays the value it was.
      # In a proved block, TapeShrinkChecker refuses a local from outside
      # being bound to the block's data (TAPE_SPEC 3.2), and
      # TapeLifetimeChecker keeps its text locals in it: any local may be
      # assigned.
      if @proved && target.is_a?(Var)
        node.value.accept(self)
        return false
      end
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
        # what it makes (`Str.build { |w| ... }`): its block's
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
      @safe = false if node.names.last? == "RisRegion" || node.names.last? == "IyiHeap"
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
      check(node.body, node.body.type?, node.args.map(&.name),
        @checker.proved?(node))
      true
    end

    private def check(body : ASTNode, value_type : Type?, block_args : Array(String),
                      proved = false) : Nil
      parts = TapeScopeChecker.parts(body)
      return unless parts
      flag, inner = parts
      # A body that puts nothing on the tape keeps its wrapper with the
      # mark off: the off mark folds to nothing in a release build.
      unless @checker.allocates?(inner)
        flag.value = false
        return
      end
      @checker.decide(body, flag, @checker.safe?(inner, value_type, @scope, @owner_tape, @params, block_args, proved))
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
  # The loaded prelude's directory, "/"-terminated: a test's patched copy
  # of `src/iyi/` (bench/*.sh mutation proofs) is the runtime as much as
  # the original, so the rules that exempt the runtime exempt it too.
  class_property prelude_dir : String? = nil
  @@expanded = {} of String => String

  def self.runtime?(location : Location?) : Bool
    file = location.try(&.original_filename)
    return true unless file
    file = file.gsub('\\', '/')
    return true if crystal?(location) || file.includes?("/src/iyi/") || file.includes?("/src/compiler/")
    return false unless dir = prelude_dir
    return true if file.starts_with?(dir)
    return false if file.starts_with?('/')
    @@expanded[file] ||= File.expand_path(file).gsub('\\', '/')
    @@expanded[file].starts_with?(dir)
  end

  # A file of the runtime or std, where a checkout or a search-path entry
  # keeps them: `src/iyi/`, `src/std/`, or `iyi/` and `std/` under an
  # `IYI_PATH` entry, as a bench's patched copy of either is.
  def self.library_file?(filename : String) : Bool
    filename = filename.gsub('\\', '/')
    return true if filename.includes?("/src/iyi/") || filename.includes?("/src/std/")
    @@library_roots ||= IyiPath.default_paths.compact_map do |entry|
      next if entry.empty? || entry == "lib"
      File.expand_path(entry).gsub('\\', '/').rstrip('/') + "/"
    end
    full = filename.starts_with?('/') ? filename : File.expand_path(filename).gsub('\\', '/')
    @@library_roots.not_nil!.any? do |root|
      full.starts_with?(root + "iyi/") || full.starts_with?(root + "std/")
    end
  end

  @@library_roots : Array(String)? = nil

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
      file.includes?("/src/compiler/") || file.ends_with?(".cr") ||
      TapeScopeRuntime.runtime?(location)
  end
end
