# ris: `while i < a.size` keeps `i` below the size, so `a[i]` and
# `a[i] = v` in its body need not check that bound again: they become
# `a.__loop_fetch(i)` and `a.__loop_store(i, v)`, which check only that
# `i` is not negative. That holds when the body assigns `a` nowhere and
# `i` only by adding one, and the array cannot shrink: `Tape::Array` and
# `Tape::String` never do, and for any other value the two calls are
# `[]` and `[]=` as written (Goose elides these checks too). In
# `while i < a.size && c`, `c` runs only after that test, so `a[i]` in
# `c` is lowered as well.
class Iyi::TapeCheckFreeLowering < Iyi::Visitor
  def self.lower(node : While) : Nil
    return if TapeScopeRuntime.crystal?(node.location)
    cond = node.cond
    rest = [] of ASTNode
    while cond.is_a?(And)
      rest << cond.right
      cond = cond.left
    end
    return unless cond.is_a?(Call) && cond.name == "<" && cond.args.size == 1
    index = cond.obj
    size = cond.args.first
    return unless index.is_a?(Var) && size.is_a?(Call) &&
                  (size.name == "size" || size.name == "bytesize")
    array = size.obj
    return unless array.is_a?(Var) && size.args.empty? && size.block.nil?
    scan = Scan.new(index.name, array.name)
    node.body.accept(scan)
    rest.each &.accept(scan)
    return if scan.unsafe
    lower = new(index.name, array.name)
    node.body.accept(lower)
    rest.each &.accept(lower)
  end

  def initialize(@index : String, @array : String)
  end

  def visit(node : Call)
    return true unless (obj = node.obj).is_a?(Var) && obj.name == @array
    return true unless node.block.nil? && node.named_args.nil?
    first = node.args.first?
    return true unless first.is_a?(Var) && first.name == @index
    if node.name == "[]" && node.args.size == 1
      node.name = "__loop_fetch"
    elsif node.name == "[]=" && node.args.size == 2
      node.name = "__loop_store"
    end
    true
  end

  def visit(node : ASTNode)
    true
  end

  # Whether the body may change `a`, or `i` other than by one up.
  class Scan < Iyi::Visitor
    getter unsafe = false

    def initialize(@index : String, @array : String)
    end

    def visit(node : Assign)
      check(node.target, node.value)
      true
    end

    def visit(node : OpAssign)
      target = node.target
      if target.is_a?(Var) && target.name == @index
        @unsafe = true unless node.op == "+" && one?(node.value)
      elsif target.is_a?(Var) && target.name == @array
        @unsafe = true
      end
      true
    end

    def visit(node : MultiAssign | UninitializedVar | TypeDeclaration | Out)
      @unsafe = true
      true
    end

    def visit(node : Block)
      @unsafe = true if node.args.any? do |arg|
                          arg.name == @index || arg.name == @array
                        end
      true
    end

    def visit(node : ASTNode)
      true
    end

    private def check(target : ASTNode, value : ASTNode) : Nil
      return unless target.is_a?(Var)
      if target.name == @array
        @unsafe = true
      elsif target.name == @index
        ok = value.is_a?(Call) && value.name == "+" &&
             one?(value.args.first?) &&
             (obj = value.obj).is_a?(Var) && obj.name == @index
        @unsafe = true unless ok
      end
    end

    private def one?(node : ASTNode?) : Bool
      node.is_a?(NumberLiteral) && node.value == "1"
    end
  end
end
