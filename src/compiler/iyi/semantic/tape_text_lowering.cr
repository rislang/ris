# ris: inside a `tape` or `local_tape` block, or a def taking a tape
# value (a tape runs while one exists), `puts "a#{b}"` and
# `print "a#{b}"` write their text on the tape. The interpolation is
# made `Str.interpolate(...)`, which appends each piece to a
# writer on the running tape; `puts` and `print` take a `Str`.
# Nothing else changes: the text goes straight to the call, so no tape
# value is held anywhere new, and with no tape running (a proc called
# later) `interpolate` builds on the heap as before.
#
# A variable is lowered too when the text only passes through it:
# `line = "a#{b}"; puts line`, where every use of `line` in its scope is
# such an assignment or a `puts`/`print` of it, all in one tape block.
# A variable the code around the block uses is left on the heap, as the
# block may not hand it a tape value.
class Iyi::TapeTextLowering < Iyi::Visitor
  SINKS = {"puts", "print"}

  def self.tape_block?(node : Call) : Bool
    node.obj.nil? && !node.block.nil? &&
      (node.name == "tape" || node.name == "local_tape")
  end

  TAPE_TYPES = {"Str", "Ary", "Tre"}

  # Whether a restriction names a tape type as a whole word. No regex:
  # the compiler built on the floor carries no pcre2.
  def self.tape_def?(node : Def) : Bool
    node.args.any? { |arg| names_tape_type?(arg.restriction.to_s) }
  end

  def self.names_tape_type?(text : String) : Bool
    word = String::Builder.new
    text.each_char do |c|
      if c.alphanumeric? || c == '_'
        word << c
      else
        return true if TAPE_TYPES.includes?(word.to_s)
        word = String::Builder.new
      end
    end
    TAPE_TYPES.includes?(word.to_s)
  end

  def self.sink?(node : Call) : Bool
    node.obj.nil? && SINKS.includes?(node.name)
  end

  def self.interpolate(arg : ASTNode) : ASTNode
    path = Path.global(["Str"]).at(arg)
    Call.new(path, "interpolate", arg.expressions).at(arg)
  end

  def visit(node : Call)
    return true unless TapeTextLowering.sink?(node)
    node.args.map! do |arg|
      arg.is_a?(StringInterpolation) ? TapeTextLowering.interpolate(arg) : arg
    end
    true
  end

  def visit(node : ASTNode)
    true
  end

  # Lowers the variables of one scope, a def's body or the program's top
  # level; *params* are the names it is given, never lowered, and *whole*
  # says the scope itself runs on a tape.
  def self.lower_scope(body : ASTNode, params : Array(String), whole : Bool) : Nil
    return if TapeScopeRuntime.crystal?(body.location)
    scan = Scan.new(whole)
    params.each { |name| scan.use(name, :other) }
    body.accept(scan)
    scan.lowerable.each do |assign|
      value = assign.value
      assign.value = interpolate(value) if value.is_a?(StringInterpolation)
    end
  end

  # Every use of each variable in a scope: in which tape block (0 for the
  # scope itself when it runs on a tape, nil for none) and how.
  class Scan < Iyi::Visitor
    record Use, region : UInt64?, kind : Symbol, assign : Assign?

    @uses = Hash(String, Array(Use)).new { |hash, key| hash[key] = [] of Use }
    @regions = [] of UInt64

    def initialize(whole : Bool)
      @regions << 0_u64 if whole
    end

    def use(name : String, kind : Symbol, assign : Assign? = nil) : Nil
      @uses[name] << Use.new(@regions.last?, kind, assign)
    end

    def lowerable : Array(Assign)
      found = [] of Assign
      @uses.each_value do |uses|
        region = uses.first.region
        next if region.nil? || uses.any? { |u| u.region != region || u.kind == :other }
        next unless uses.any? { |u| u.kind == :sink }
        uses.each { |u| u.assign.try { |assign| found << assign } }
      end
      found
    end

    def visit(node : Assign)
      target = node.target
      if target.is_a?(Var)
        kind = node.value.is_a?(StringInterpolation) ? :assign : :other
        use(target.name, kind, node)
        node.value.accept(self)
        return false
      end
      true
    end

    def visit(node : Var)
      use(node.name, :other)
      false
    end

    def visit(node : Call)
      if TapeTextLowering.tape_block?(node)
        node.args.each(&.accept(self))
        @regions << node.object_id
        node.block.try(&.accept(self))
        @regions.pop
        return false
      end
      return true unless TapeTextLowering.sink?(node)
      node.args.each do |arg|
        arg.is_a?(Var) ? use(arg.name, :sink) : arg.accept(self)
      end
      node.named_args.try(&.each(&.accept(self)))
      node.block.try(&.accept(self))
      false
    end

    # A nested def, type or macro is a scope of its own.
    def visit(node : Def | ClassDef | ModuleDef | Macro | EnumDef | LibDef)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end
end
