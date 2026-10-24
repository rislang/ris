# ris: a `Str`'s raw pointer stays in the library. Its
# `to_unsafe` compiles and then reads whatever follows its bytes - the next
# value, or, once the scope has ended, the next scope's - and
# `Str.new(pointer, size)` makes a view of any address. The
# checkers that keep a tape value inside its scope do not see either, so
# outside the tape's runtime (`src/iyi/`) and a `std/` def marked
# `@[TapeUnsafe]` both are refused, and a program reads a tape string
# through the bounds-checked `[]`, `each_byte` and `[start, count]` instead. A raw pointer the program makes itself
# (`Pointer.new`) is outside this rule: iyi has no unsafe blocks for it.
class Iyi::TapePointerChecker
  getter program : Program
  @seen = Set(UInt64).new
  @defs = [] of Def

  def initialize(@program)
  end

  def run(node : ASTNode) : Nil
    node.accept Collector.new(self)
    check node
    @defs.each { |a_def| check a_def.body }
  end

  def reach(a_def : Def) : Nil
    return if TapeRules.runtime?(@program, a_def.location) || !@seen.add?(a_def.object_id)
    if TapeRules.unsafe?(@program, a_def)
      TapeFfiFlow.new(self).check(a_def)
    else
      @defs << a_def
    end
    a_def.body.accept Collector.new(self)
  end

  private def check(node : ASTNode) : Nil
    node.accept Finder.new(self)
  end

  # The pointer *node* takes out of tape text or views as tape text: a
  # `Str`'s `to_unsafe`, or the pointer `Str.new` views.
  def pointer_of(node : Call) : ASTNode?
    return node if node.name == "to_unsafe" && (receiver = node.obj) && tape_string?(receiver.type?)
    node.args[0] if view?(node)
  end

  private def view?(node : Call) : Bool
    node.name == "new" && node.args.size == 2 &&
      !!node.target_defs.try &.any? { |target| tape_string_class?(target.owner) }
  end

  # Whether *node* is `Str::Builder#unsafe_append`, which yields a
  # pointer into the tape: its block's first parameter.
  def yields_pointer?(node : Call) : Bool
    node.name == "unsafe_append" &&
      !!node.target_defs.try &.any? { |target| target.owner.to_s == "Str::Builder" }
  end

  def refuse?(node : Call) : String?
    return nil if TapeRules.runtime?(@program, node.location)
    if yields_pointer?(node)
      return "`#{node.name}` outside a @[TapeUnsafe] def: it yields a pointer into the tape, for a system call to write into.\n\nWrite tape text with a Str::Builder's `<<`, `push` and `append`."
    end
    return nil unless pointer_of(node)
    unless view?(node)
      return "`to_unsafe` of a Str outside a @[TapeUnsafe] def: the pointer reads past its bytes as readily as within them, and after its scope the next scope's.\n\nRead it with `[]`, `[start, count]` or `each_byte`, which check their bounds."
    end
    "`Str.new(pointer, size)` outside a @[TapeUnsafe] def: a view of any address, which the tape's checks do not see.\n\nCopy a String onto the tape with `Str.new(text)`, view one with `Str.view(text)`, or a part of a tape string with `[start, count]`."
  end

  private def tape_string?(type : Type?) : Bool
    return false unless type
    type.remove_typedef.to_s == "Str"
  end

  private def tape_string_class?(owner : Type) : Bool
    owner.metaclass? && owner.instance_type.to_s == "Str"
  end

  class Collector < Visitor
    def initialize(@checker : TapePointerChecker)
    end

    def visit(node : Call)
      node.target_defs.try &.each { |a_def| @checker.reach(a_def) }
      true
    end

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end

  class Finder < Visitor
    def initialize(@checker : TapePointerChecker)
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      if reason = @checker.refuse?(node)
        node.raise reason
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

# ris: `@[TapeUnsafe]` is for the FFI and OS boundary only. Each pointer
# a marked def takes out of tape text, views as tape text, or is yielded
# by `Writer#unsafe_append`, must be
# handed on to a `lib` fun, a `__sys` system call or an `asm` system call:
# as an argument, through locals, a local buffer it is stored in (an
# iovec), pointer arithmetic, `as` and `address`, and on through the
# parameters of the defs it is passed to. A codec that
# walks the bytes by pointer is not the boundary; it reads with `[]` and
# `each_byte`. Copying memory (`LibTapeCopy`, `LibIntrinsics`, C's `mem*`)
# is not the OS. An IO's pointer write is: which IO it is, a file, socket
# or pipe, is known at run time, and a program holding only the abstract
# IO (an editor opening one module) has no concrete write to follow.
class Iyi::TapeFfiFlow
  POINTER_OPS = {"+", "-", "address", "to_i64", "to_u64", "pointer"}
  MEMORY_LIBS = {"LibTapeCopy", "LibIntrinsics"}
  IO_WRITES   = {"write", "write_string", "unbuffered_write"}

  # Whether parameter *index* of a def reaches the OS, by def and index:
  # false while it is looked at, which ends a recursion.
  @reaches = {} of {UInt64, Int32} => Bool

  def initialize(@checker : TapePointerChecker)
  end

  def check(a_def : Def) : Nil
    # The `new` made from an `initialize` carries its annotations; the
    # `initialize` is checked itself.
    return if a_def.new?
    pointers = [] of ASTNode
    yielders = [] of Call
    body_nodes(a_def.body) do |node|
      next unless node.is_a?(Call)
      if pointer = @checker.pointer_of(node)
        pointers << pointer
      elsif @checker.yields_pointer?(node)
        yielders << node
      end
    end
    yielders.each do |call|
      block = call.block
      param = block.try &.args.first?
      next if block && param && reaches?(block.body, nil, param.name)
      call.raise "the pointer `#{call.name}` yields reaches no `lib` fun or system call: the mark is for the FFI and OS boundary only.\n\nWrite tape text with a Str::Builder's `<<`, `push` and `append`."
    end
    if pointers.empty? && yielders.empty?
      a_def.raise "@[TapeUnsafe] on a def that hands no tape pointer to the OS: the mark is for the FFI and OS boundary only.\n\nRead tape text with `[]`, `[start, count]` or `each_byte`, and copy it off the tape by name with `to_heap`."
    end
    pointers.each do |pointer|
      next if reaches?(a_def.body, pointer, nil)
      pointer.raise "a tape pointer in a @[TapeUnsafe] def that reaches no `lib` fun or system call: the mark is for the FFI and OS boundary only.\n\nRead tape text with `[]`, `[start, count]` or `each_byte`, and write it with a Str::Builder."
    end
  end

  # Whether *origin*, or the parameter named *param*, is handed to the OS
  # within *body*.
  private def reaches?(body : ASTNode, origin : ASTNode?, param : String?) : Bool
    names = Set(String).new
    names << param if param
    assigns = [] of Assign
    calls = [] of Call
    asms = [] of Asm
    body_nodes(body) do |node|
      assigns << node if node.is_a?(Assign)
      calls << node if node.is_a?(Call)
      asms << node if node.is_a?(Asm)
    end
    loop do
      grew = false
      assigns.each do |assign|
        target = assign.target
        next unless target.is_a?(Var) && !names.includes?(target.name)
        next unless pointer?(assign.value, origin, names)
        names << target.name
        grew = true
      end
      # `words[i] = pointer.address`: the buffer an OS structure is built
      # in (an iovec) carries the pointer on to the call it is handed to.
      calls.each do |call|
        buffer = call.obj
        next unless call.name == "[]=" && buffer.is_a?(Var) && !names.includes?(buffer.name)
        next unless (value = call.args.last?) && pointer?(value, origin, names)
        names << buffer.name
        grew = true
      end
      break unless grew
    end
    return true if asms.any? &.inputs.try &.any? { |input| pointer?(input.exp, origin, names) }
    calls.any? do |call|
      call.args.each_with_index.any? do |arg, index|
        pointer?(arg, origin, names) && to_os?(call, index)
      end
    end
  end

  private def pointer?(node : ASTNode, origin : ASTNode?, names : Set(String)) : Bool
    return true if origin && node.same?(origin)
    case node
    when Var
      names.includes?(node.name)
    when Cast
      pointer?(node.obj, origin, names)
    when Expressions
      !node.expressions.empty? && pointer?(node.expressions.last, origin, names)
    when Call
      return false unless POINTER_OPS.includes?(node.name)
      return true if (obj = node.obj) && pointer?(obj, origin, names)
      node.name == "+" && node.args.any? { |arg| pointer?(arg, origin, names) }
    else
      false
    end
  end

  private def to_os?(call : Call, index : Int32) : Bool
    targets = call.target_defs
    return false unless targets
    targets.any? do |target|
      next os?(target) if target.is_a?(External)
      next true if target.name.starts_with?("__sys") || io_write?(target)
      next false unless index < target.args.size
      key = {target.object_id, index}
      found = @reaches[key]?
      next found unless found.nil?
      @reaches[key] = false
      @reaches[key] = reaches?(target.body, nil, target.args[index].name)
    end
  end

  private def io_write?(target : Def) : Bool
    return false unless IO_WRITES.includes?(target.name)
    # `IO` is an alias, of `IyiIO` in ris's prelude.
    return false unless io = @checker.program.types["IO"]?.try(&.remove_alias)
    owner = target.owner
    owner == io || owner.ancestors.includes?(io)
  end

  private def os?(external : External) : Bool
    return false if MEMORY_LIBS.includes?(external.owner.to_s)
    !external.real_name.starts_with?("mem")
  end

  private def body_nodes(node : ASTNode, &block : ASTNode ->) : Nil
    node.accept Walker.new(block)
  end

  class Walker < Visitor
    def initialize(@block : ASTNode ->)
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      @block.call(node)
      true
    end

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      @block.call(node)
      true
    end
  end
end

# Where the tape's rules (TapePointerChecker, TapeEscapeChecker,
# TapeRefillChecker) do not reach. The tape's own runtime (`src/iyi/`, and
# Crystal's `.cr` code, which has no tape) builds the rules' primitives from
# raw pointers. A `std/` module is under the rules like any program; a def
# of one that must hand a pointer to the OS or copy a view out to keep a
# `String` API says so with `@[TapeUnsafe]`, and only its body is let
# through. The mark is refused outside `std/`: a program reads tape text
# through `[]`, `[start, count]` and `each_byte`.
module Iyi::TapeRules
  # The prelude also where it was loaded from: a test copies it out of
  # `src/iyi/` to change it.
  def self.runtime?(program : Program, location : Location?) : Bool
    file = location.try(&.original_filename)
    return false unless file
    file = file.gsub('\\', '/')
    file.includes?("/src/iyi/") || file.ends_with?(".cr") ||
      TapeScopeRuntime.prelude?(program, location)
  end

  def self.std?(location : Location?) : Bool
    file = location.try(&.original_filename)
    return false unless file
    file.gsub('\\', '/').includes?("/std/")
  end

  def self.unsafe?(program : Program, a_def : Def) : Bool
    return false unless ann = a_def.annotation(program.tape_unsafe_annotation)
    unless std?(a_def.location) || runtime?(program, a_def.location)
      ann.raise "@[TapeUnsafe] outside a `std/` module: it lifts the tape's rules, which keep a program's tape values in their scope.\n\nRead tape text with `[]`, `[start, count]` or `each_byte`, and copy it off the tape by name with `to_heap`."
    end
    true
  end
end
