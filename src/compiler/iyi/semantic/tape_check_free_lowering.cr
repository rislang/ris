# ris: `while i < a.size` keeps `i` below the size, so `a[i]` and
# `a[i] = v` in its body need not check that bound again: they become
# `a.__loop_fetch(i)` and `a.__loop_store(i, v)`, which check only that
# `i` is not negative. That holds when the body assigns `a` nowhere and
# `i` only by adding one (`&+` too: a wrapped `i` is negative), and the
# array cannot shrink: `Tape::Array` and `Tape::String` never do, and
# for any other value the two calls are `[]` and `[]=` as written
# (Goose elides these checks too). In
# `while i < a.size && c`, `c` runs only after that test, so `a[i]` in
# `c` is lowered as well; so is `c` in `if i < a.size && c`.
#
# `while i + K <= a.bytesize`, with `K` a literal and `i` stepped by
# `i += K`, keeps `K` bytes from `i` in range: `a.read_bytes_at(I, i)`
# becomes `a.__loop_read_bytes_at(I, i, K)`, unchecked when `I` fits
# in `K` bytes, and the test is `i <= a.bytesize &- K`, which cannot
# overflow. The size may be a local `n` set once by `n = a.bytesize`
# where `a` is set at most once too (`Binding`).
class Iyi::TapeCheckFreeLowering < Iyi::Visitor
  # The largest step `i + K` is taken for: a word or a few.
  MAX_STEP = 64

  def self.lower(node : While, scope : ASTNode?, params : Array(String)) : Nil
    return if TapeScopeRuntime.crystal?(node.location)
    test = guard(node.cond, scope, params)
    return unless test
    left, rest, index, array, size, step = test
    scan = Scan.new(index, array, size, step)
    node.body.accept(scan)
    strict = Scan.new(index, array, size, 0)
    rest.each &.accept(strict)
    return if scan.unsafe || strict.unsafe
    lower = new(index, array, step)
    node.body.accept(lower)
    rest.each &.accept(lower)
    no_overflow(left, step)
  end

  # `if i < a.size && c`: only `c` runs under the test.
  def self.lower(node : If, scope : ASTNode?, params : Array(String)) : Nil
    return if TapeScopeRuntime.crystal?(node.location)
    test = guard(node.cond, scope, params)
    return unless test
    left, rest, index, array, size, step = test
    return if rest.empty?
    strict = Scan.new(index, array, size, 0)
    rest.each &.accept(strict)
    return if strict.unsafe
    lower = new(index, array, step)
    rest.each &.accept(lower)
    no_overflow(left, step)
  end

  # The bound test leftmost in *cond*, and the `&&` operands after it:
  # `i < s` (step 1) or `i + K <= s` (step K), with `s` the size of `a`.
  private def self.guard(cond : ASTNode, scope : ASTNode?, params : Array(String))
    rest = [] of ASTNode
    while cond.is_a?(And)
      rest << cond.right
      cond = cond.left
    end
    return unless cond.is_a?(Call) && cond.args.size == 1
    left = cond.obj
    if cond.name == "<"
      step = 1
    elsif cond.name == "<=" && left.is_a?(Call) && left.name == "+" &&
          left.args.size == 1 && (k = literal(left.args.first))
      step = k
      left = left.obj
    else
      return
    end
    return unless left.is_a?(Var)
    size = cond.args.first
    array = nil
    local = nil
    if size.is_a?(Call)
      array = sized(size)
    elsif size.is_a?(Var) && scope
      local = size.name
      array = Binding.find(scope, params, local)
    end
    return unless array
    {cond, rest, left.name, array, local, step}
  end

  # `a.size` or `a.bytesize`: the name of `a`.
  protected def self.sized(node : ASTNode) : String?
    return unless node.is_a?(Call) && (node.name == "size" || node.name == "bytesize")
    obj = node.obj
    obj.name if obj.is_a?(Var) && node.args.empty? && node.block.nil?
  end

  protected def self.literal(node : ASTNode?) : Int32?
    return unless node.is_a?(NumberLiteral) && node.kind.i32?
    value = node.value.to_i?
    value if value && 1 <= value <= MAX_STEP
  end

  # `i + K <= s` as `i <= s &- K`: `s` is not negative, so this cannot
  # overflow where `i + K` could.
  private def self.no_overflow(test : Call, step : Int32) : Nil
    return if step == 1 && test.name == "<"
    sum = test.obj.as(Call)
    size = test.args.first
    test.obj = sum.obj
    test.args = [Call.new(size, "&-", NumberLiteral.new(step)).at(size)] of ASTNode
  end

  def initialize(@index : String, @array : String, @step : Int32)
  end

  def visit(node : Call)
    return true unless (obj = node.obj).is_a?(Var) && obj.name == @array
    return true unless node.block.nil? && node.named_args.nil?
    if node.name == "read_bytes_at" && node.args.size == 2 &&
       (at = node.args[1]).is_a?(Var) && at.name == @index
      node.name = "__loop_read_bytes_at"
      node.args << NumberLiteral.new(@step).at(node)
      return true
    end
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

  # Whether the body may change `a` or the size `n`, or `i` other than
  # by one step up. A step of 0 allows no change of `i` at all.
  class Scan < Iyi::Visitor
    getter unsafe = false

    def initialize(@index : String, @array : String, @size : String?, @step : Int32)
    end

    def visit(node : Assign)
      check(node.target, node.value)
      true
    end

    def visit(node : OpAssign)
      target = node.target
      if target.is_a?(Var) && target.name == @index
        @unsafe = true unless (node.op == "+" || node.op == "&+") && step?(node.value)
      elsif target.is_a?(Var) && fixed?(target.name)
        @unsafe = true
      end
      true
    end

    def visit(node : MultiAssign | UninitializedVar | TypeDeclaration | Out)
      @unsafe = true
      true
    end

    def visit(node : PointerOf)
      exp = node.exp
      @unsafe = true if exp.is_a?(Var) && (exp.name == @index || fixed?(exp.name))
      true
    end

    def visit(node : Block)
      @unsafe = true if node.args.any? do |arg|
                          arg.name == @index || fixed?(arg.name)
                        end
      true
    end

    def visit(node : ASTNode)
      true
    end

    private def fixed?(name : String) : Bool
      name == @array || name == @size
    end

    private def check(target : ASTNode, value : ASTNode) : Nil
      return unless target.is_a?(Var)
      if fixed?(target.name)
        @unsafe = true
      elsif target.name == @index
        ok = value.is_a?(Call) && (value.name == "+" || value.name == "&+") &&
             step?(value.args.first?) &&
             (obj = value.obj).is_a?(Var) && obj.name == @index
        @unsafe = true unless ok
      end
    end

    private def step?(node : ASTNode?) : Bool
      @step > 0 && node.is_a?(NumberLiteral) && node.value == @step.to_s
    end
  end

  # The array whose size the local *size* holds: *size* is set once in
  # *scope*, by `size = a.size` or `a.bytesize`, and `a` at most once (a
  # parameter counts), so *size* is that size wherever it is read.
  class Binding < Iyi::Visitor
    def self.find(scope : ASTNode, params : Array(String), size : String) : String?
      return if params.includes?(size)
      sizes = new(size)
      scope.accept(sizes)
      return unless sizes.count == 1 && (array = sizes.array)
      arrays = new(array)
      scope.accept(arrays)
      count = arrays.count + (params.includes?(array) ? 1 : 0)
      array if count <= 1
    end

    getter count = 0
    getter array : String?

    def initialize(@name : String)
    end

    def visit(node : Assign)
      target = node.target
      if target.is_a?(Var) && target.name == @name
        @count += 1
        @array = TapeCheckFreeLowering.sized(node.value)
      end
      true
    end

    def visit(node : OpAssign | MultiAssign | UninitializedVar | TypeDeclaration | Out | PointerOf | Arg)
      @count += 2 if mentions?(node)
      true
    end

    def visit(node : Block)
      @count += 2 if node.args.any? &.name.==(@name)
      true
    end

    def visit(node : ASTNode)
      true
    end

    private def mentions?(node : ASTNode) : Bool
      case node
      when Arg
        node.name == @name
      when MultiAssign
        node.targets.any? { |t| t.is_a?(Var) && t.name == @name }
      when OpAssign, UninitializedVar, TypeDeclaration, Out, PointerOf
        exp = case node
              when OpAssign         then node.target
              when UninitializedVar then node.var
              when TypeDeclaration  then node.var
              when Out              then node.exp
              when PointerOf        then node.exp
              end
        exp.is_a?(Var) && exp.name == @name
      else
        false
      end
    end
  end
end
