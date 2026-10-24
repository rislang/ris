# ris: `while @x.offset < lim` over a `Str::Scanner` field reads and
# moves the offset through `@x` at every byte, and LLVM keeps storing it
# back, as the text's bytes might be the field. The loop is run on two
# locals instead, the text and a cursor:
#
#     __text_x = @x.string
#     __cursor_x = @x.offset
#     __loop_x = while __cursor_x < lim ... end
#     @x.advance(__cursor_x &- @x.offset)
#     __loop_x
#
# `@x.offset` is the cursor, `@x.string` the text, `@x.advance(k)` adds
# `k` to the cursor and `@x.offset = v` sets both. The offset is written
# back where the loop ends, at a `break` too, and before a `return`; a
# call that may read or move `@x` (any but an operator, a conversion or
# a read of the text) is made with the offset written back, and both
# locals are read again after it. A body with a block, a `yield`, a
# macro or another use of `@x` is left as written, as is one where `@x`
# is not declared `Str::Scanner` in the class the def is in.
class Iyi::TapeCursorLowering < Iyi::Transformer
  OPERATORS = %w(== != < > <= >= + - * / // % & | ^ << >> &+ &- &* ! ~)
  PLAIN     = %w(to_i to_i32 to_i64 to_u8 to_u16 to_u32 to_u64 chr bytesize size
    unsafe_to_u8 unsafe_to_u64 unsafe_to_i64 unsafe_chr [] []?)

  def self.lower(node : While, scanners : Array(String)) : ASTNode?
    return if scanners.empty? || TapeScopeRuntime.crystal?(node.location)
    left = node.cond
    while left.is_a?(And)
      left = left.left
    end
    return unless left.is_a?(Call) && left.name == "<" && left.args.size == 1
    field = offset_of(left.obj)
    return unless field && scanners.includes?(field)
    return unless Fit.new(field).fits?(node)
    lower = new(field)
    node.cond = node.cond.transform(lower)
    node.body = node.body.transform(lower)
    return if lower.refused
    text, cursor, loop = lower.text, lower.cursor, "__loop_#{field}"
    locate Expressions.new([
      Assign.new(Var.new(text), Call.new(InstanceVar.new("@#{field}"), "string")),
      Assign.new(Var.new(cursor), Call.new(InstanceVar.new("@#{field}"), "offset")),
      Assign.new(Var.new(loop), node),
      lower.store,
      Var.new(loop),
    ] of ASTNode), node
  end

  # *node* and what is made for it get *at*'s location where they have
  # none: a call with none fails LLVM's debug-info check.
  protected def self.locate(node : ASTNode, at : ASTNode) : ASTNode
    node.accept(Locate.new(at.location)) if at.location
    node
  end

  # `@x.offset`: the name `x`.
  protected def self.offset_of(node : ASTNode?) : String?
    field_call(node, "offset", 0)
  end

  protected def self.field_call(node : ASTNode?, name : String, args : Int32) : String?
    return unless node.is_a?(Call) && node.name == name && node.args.size == args
    return unless node.block.nil? && node.block_arg.nil? && node.named_args.nil?
    obj = node.obj
    obj.name.lchop('@') if obj.is_a?(InstanceVar)
  end

  getter text : String
  getter cursor : String
  getter refused = false
  @temps = 0

  def initialize(@field : String)
    @text = "__text_#{@field}"
    @cursor = "__cursor_#{@field}"
  end

  # `@x.advance(cursor &- @x.offset)`: the offset written back.
  def store : ASTNode
    ivar = InstanceVar.new("@#{@field}")
    back = Call.new(Var.new(@cursor), "&-", Call.new(ivar.clone, "offset"))
    Call.new(ivar, "advance", back)
  end

  def transform(node : Call)
    if TapeCursorLowering.field_call(node, "offset", 0) == @field
      return Var.new(@cursor).at(node)
    elsif TapeCursorLowering.field_call(node, "string", 0) == @field
      return Var.new(@text).at(node)
    elsif TapeCursorLowering.field_call(node, "advance", 0) == @field
      return TapeCursorLowering.locate step(node, NumberLiteral.new(1)), node
    elsif TapeCursorLowering.field_call(node, "advance", 1) == @field
      return TapeCursorLowering.locate step(node, node.args.first.transform(self)), node
    elsif TapeCursorLowering.field_call(node, "offset=", 1) == @field
      node.args = [node.args.first.transform(self)] of ASTNode
      return TapeCursorLowering.locate Assign.new(Var.new(@cursor), node), node
    end
    if obj = node.obj
      node.obj = obj.transform(self)
    end
    transform_many node.args
    return node if plain?(node)
    # A call that may see `@x`: its arguments must not move the cursor,
    # since the offset is written back before them.
    @refused = true if node.args.any? { |arg| Moves.new(@cursor).moves?(arg) }
    temp = "__call_#{@field}_#{@temps += 1}"
    TapeCursorLowering.locate Expressions.new([
      store,
      Assign.new(Var.new(temp), node),
      Assign.new(Var.new(@text), Call.new(InstanceVar.new("@#{@field}"), "string")),
      Assign.new(Var.new(@cursor), Call.new(InstanceVar.new("@#{@field}"), "offset")),
      Var.new(temp),
    ] of ASTNode), node
  end

  def transform(node : Return)
    exp = node.exp.try &.transform(self)
    temp = "__return_#{@field}_#{@temps += 1}"
    exps = [] of ASTNode
    if exp
      exps << Assign.new(Var.new(temp), exp)
      node.exp = Var.new(temp)
    end
    exps << store
    exps << node
    TapeCursorLowering.locate Expressions.new(exps), node
  end

  def transform(node : ASTNode)
    super
  end

  private def step(node : Call, count : ASTNode) : ASTNode
    sum = Call.new(Var.new(@cursor), "&+", count)
    Assign.new(Var.new(@cursor), sum).at(node)
  end

  # An operator or a conversion, or a read of the text: none sees `@x`.
  private def plain?(node : Call) : Bool
    return false unless node.block.nil? && node.block_arg.nil? && node.named_args.nil?
    obj = node.obj
    return false unless obj
    return true if obj.is_a?(Var) && obj.name == @text
    OPERATORS.includes?(node.name) || PLAIN.includes?(node.name)
  end

  class Locate < Iyi::Visitor
    def initialize(@location : Location?)
    end

    def visit(node : ASTNode)
      node.location ||= @location
      true
    end
  end

  # Whether a loop may be lowered: the body uses `@x` only for the four
  # calls taken, and runs no code it cannot see.
  class Fit < Iyi::Visitor
    def initialize(@field : String)
      @ok = true
    end

    def fits?(node : While) : Bool
      node.cond.accept(self)
      node.body.accept(self)
      @ok
    end

    def visit(node : Call)
      obj = node.obj
      if obj.is_a?(InstanceVar) && obj.name == "@#{@field}"
        name = node.name
        @ok = false unless node.block.nil? && node.named_args.nil? &&
                           {"offset", "string", "advance", "offset="}.includes?(name)
        node.args.each &.accept(self)
        return false
      end
      @ok = false if node.block || node.block_arg
      true
    end

    def visit(node : InstanceVar)
      @ok = false if node.name == "@#{@field}"
      true
    end

    def visit(node : Yield | Block | ProcLiteral | MacroExpression | MacroIf | MacroFor | MacroVerbatim | MacroLiteral | Def | While)
      @ok = false unless node.is_a?(While)
      true
    end

    def visit(node : ASTNode)
      true
    end
  end

  # Whether an expression moves the cursor.
  class Moves < Iyi::Visitor
    def initialize(@cursor : String)
      @moves = false
    end

    def moves?(node : ASTNode) : Bool
      node.accept(self)
      @moves
    end

    def visit(node : Assign)
      target = node.target
      @moves = true if target.is_a?(Var) && target.name == @cursor
      true
    end

    def visit(node : ASTNode)
      true
    end
  end
end
