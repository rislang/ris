# Every def, loop round and block frees its scratch when it ends (SPEC
# 1.1): each begins with a mark of the caller's allocation boundary and
# resets to it at its end, always. A def's or block's value goes through
# RESULT: a String or Array made in the scratch moves down to the
# boundary (SPEC 1.5); any other tape value it returns views older
# storage, as TapeShrinkChecker proves or refuses (SPEC 1.9, 3.6). A def
# whose body is one call (or a choice between two, or a tuple of calls)
# is not marked: the call builds its result where the caller keeps it. `next` and `break` in a loop reset first; `next`
# in a block and `return` in a def hand their value through RESULT.
class Iyi::TapeScopeChecker
  MARK   = "__iyi_scope_mark"
  RESET  = "__iyi_scope_reset"
  RESULT = "__iyi_scope_result"
  RESULT_AT = "__iyi_scope_result_at"

  def self.declares?(body : ASTNode) : Bool
    nodes = body.is_a?(Expressions) ? body.expressions : [body]
    nodes.any? do |node|
      node.is_a?(Def) || node.is_a?(ClassDef) || node.is_a?(ModuleDef) ||
        node.is_a?(Macro) || node.is_a?(EnumDef) || node.is_a?(Alias) ||
        node.is_a?(Include) || node.is_a?(Extend) || node.is_a?(VisibilityModifier) ||
        node.is_a?(Annotation)
    end
  end

  # A body that is one call, which builds its value in the caller's
  # destination itself.
  def self.one_call?(body : ASTNode) : Bool
    while body.is_a?(Expressions) && body.expressions.size == 1
      body = body.expressions.first
    end
    # A tuple of calls is built where each call would be: in the caller's
    # destination (a pipe's two ends).
    if body.is_a?(TupleLiteral)
      return !body.elements.empty? && body.elements.all? { |e| one_call?(e) }
    end
    # So is a choice between two calls: whichever runs builds there. What
    # the condition makes stays in the caller's scratch, freed with it.
    # A nil branch builds nothing.
    if body.is_a?(If)
      return {body.then, body.else}.all? { |b| b.is_a?(NilLiteral) || one_call?(b) } &&
             !(body.then.is_a?(NilLiteral) && body.else.is_a?(NilLiteral))
    end
    body.is_a?(Call) && body.name != "raise"
  end

  # Named-argument wrappers are constructors too: their fields and
  # temporaries are built in the caller's destination.
  def self.constructor?(node : Def) : Bool
    node.name == "new" || node.name.starts_with?("new:") ||
      node.name == "initialize" || node.name.starts_with?("initialize:")
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
    # A constructor builds in its caller's destination.
    return if node.is_a?(Def) &&
              (node.abstract? || constructor?(node))
    return if node.is_a?(Def) && one_call?(body)
    # A block that declares methods or types is a macro's body (`record
    # ... do def ... end end`), not code that runs: wrapping it would put
    # the declarations inside an expression.
    return if node.is_a?(Block) && declares?(body)
    on = BoolLiteral.new(true).at(body)
    # Named by the body's file: an artifact's def keeps its build's names,
    # and a consumer's block inlined into it must not take them again.
    mark = program.new_temp_var(node).at(body)
    value = program.new_temp_var(node).at(body)
    body = case node
           when Def   then body.transform(Returns.new(mark))
           when Block then body.transform(Exits.new(mark, true))
           else            body.transform(Exits.new(mark, false))
           end
    cleanup = if node.is_a?(While)
                Call.new(nil, RESET, mark.clone, global: true).at(body)
              elsif node.is_a?(Block)
                # Through the slot, so a body that never ends (NoReturn)
                # still types the block by `value`.
                Call.new(nil, RESULT_AT, [mark.clone,
                  PointerOf.new(value.clone).at(body)] of ASTNode,
                  global: true).at(body)
              else
                result = Call.new(nil, RESULT,
                  [mark.clone, value.clone] of ASTNode, global: true).at(body)
                Assign.new(value.clone, result).at(body)
              end
    node.body = Expressions.new([
      Assign.new(mark, Call.new(nil, MARK, on, global: true).at(body)).at(body),
      Assign.new(value, body).at(body),
      cleanup,
      value.clone,
    ] of ASTNode).at(body)
  end

  # The pieces of a marked body: the flag and the body as written.
  # A body that never ends (NoReturn) keeps only the first two: typing
  # drops what follows it, and every exit is a `return` through RESULT.
  def self.parts(node : ASTNode) : {BoolLiteral, ASTNode}?
    return nil unless node.is_a?(Expressions)
    size = node.expressions.size
    return nil unless size >= 2
    first, second = node.expressions[0], node.expressions[1]
    return nil unless first.is_a?(Assign)
    call = first.value
    return nil unless call.is_a?(Call) && call.name == MARK
    flag = call.args.first?
    return nil unless flag.is_a?(BoolLiteral)
    return {flag, second.value} if second.is_a?(Assign) && size <= 4
    # Typing may inline a NoReturn body in place of its assignment.
    {flag, Expressions.new(node.expressions[1..]).at(node)}
  end

  getter graph : TapeCallGraph

  def initialize(@program : Program, @graph : TapeCallGraph)
  end

  # A scope that puts nothing on the tape has nothing to free: its mark
  # is turned off, which folds to nothing in a release build.
  def run(node : ASTNode) : Nil
    @graph.defs.each_value { |target| off(target.body) }
    node.accept(Finder.new(self))
  end

  def off(body : ASTNode) : Nil
    return unless parts = TapeScopeChecker.parts(body)
    flag, inner = parts
    flag.value = false unless @graph.allocates?(inner)
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

  # A loop round's `next` and `break` reset before they leave it; a
  # block's `next` and `break`, and a loop's `break` with a value, hand
  # their value through RESULT. Nested loops, blocks
  # and defs own their own marks.
  class Exits < Transformer
    def initialize(@mark : Var, @block : Bool)
    end

    def transform(node : Next)
      if @block
        exp = node.exp || NilLiteral.new.at(node)
        node.exp = Call.new(nil, RESULT, [@mark.clone, exp] of ASTNode,
          global: true).at(node)
        node
      else
        reset(node)
      end
    end

    # A `break` leaves the block (or loop) too: its scratch is freed on
    # the way out, its value handed through RESULT (SPEC 1.1: every exit
    # releases).
    def transform(node : Break)
      return reset(node) unless @block || node.exp
      exp = node.exp || NilLiteral.new.at(node)
      node.exp = Call.new(nil, RESULT, [@mark.clone, exp] of ASTNode,
        global: true).at(node)
      node
    end

    private def reset(node : ASTNode) : ASTNode
      Expressions.new([
        Call.new(nil, RESET, @mark.clone, global: true).at(node),
        node,
      ] of ASTNode).at(node)
    end

    def transform(node : Def | While | Block | ProcLiteral)
      node
    end
  end

  class Finder < Visitor
    def initialize(@checker : TapeScopeChecker)
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
      end
      true
    end

    def visit(node : While | Block)
      @checker.off(node.body)
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
