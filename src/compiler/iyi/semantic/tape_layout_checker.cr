# ris: the layout half of tape memory. A tape is one line with one end, and
# a container grows in place only while it is that end. In a loop where a
# container made before the loop grows and anything else is put on the tape
# - a new container, a `TapeString.build`, another container growing, or a
# call that does any of these - the container is never the end when it
# grows, so every growth copies it and leaves the old copy until the scope
# ends: measured slower than the GC heap (TAPE_DESIGN.md, "Layout"). Such a
# loop is refused. What stays allowed: one container growing in a loop with
# nothing else put on the tape (a writer streaming a response, a
# `TapeStream` building a tree in document order), and a container made at
# its final size, `TapeArray(T).new(count) { |i| ... }`, which never grows.
#
# Every block counts as a loop, as one may run many times. What a method
# puts on the tape is summarized over the call graph to a fixpoint, so a
# recursive parser is seen whole. The containers' own methods in tape.iyi,
# and code that reaches the tape through raw pointers, are outside the rule.
class Iyi::TapeLayoutChecker
  GROWS = {
    "TapeWriter" => {"push", "append", "append_int", "append_html_escaped", "reserve"},
    "TapeArray"  => {"push"},
    "TapeStream" => {"leaf", "open"},
  }

  # What a method does to the tape: the parameters (by index) and instance
  # variables it grows, and whether it puts anything else there.
  record Summary, params : Set(Int32), ivars : Set(String), allocs : String? do
    def self.empty
      new(Set(Int32).new, Set(String).new, nil)
    end
  end

  # What a piece of code does to the tape: the containers it grows, by the
  # variable that names them, and the first other allocation.
  class Effects
    getter grows = Set(String).new
    property alloc : ASTNode? = nil
    property what = ""

    def allocate(node : ASTNode, what : String) : Nil
      return if @alloc
      @alloc = node
      @what = what
    end
  end

  @program : Program
  @summaries = {} of UInt64 => Summary
  @defs = [] of Def
  @seen = Set(UInt64).new

  def initialize(@program)
  end

  def run(node : ASTNode) : Nil
    collect node
    changed = true
    while changed
      changed = false
      @defs.each do |a_def|
        summary = summarize(a_def)
        old = @summaries[a_def.object_id]?
        # A description, once found, is kept: through a recursive call it
        # would otherwise grow on every round and never settle.
        if old && (kept = old.allocs)
          summary = summary.copy_with(allocs: kept)
        end
        if old != summary
          @summaries[a_def.object_id] = summary
          changed = true
        end
      end
    end
    check node
    @defs.each { |a_def| check a_def.body }
  end

  def self.container(type : Type?) : String?
    return nil unless type
    type = type.remove_typedef
    name = type.is_a?(GenericClassInstanceType) ? type.generic_type.name : type.to_s
    GROWS.has_key?(name) ? name : nil
  end

  # The tape's own types, whose methods are the rule's primitives.
  private def internal?(a_def : Def) : Bool
    owner = a_def.owner
    owner = owner.instance_type if owner.metaclass?
    owner = owner.generic_type if owner.is_a?(GenericClassInstanceType)
    owner.to_s.in?("TapeString", "TapeWriter", "TapeArray", "TapeStream",
      "TapeStreamEntry", "Tape", "IyiRegion")
  end

  # Every reachable instantiated method outside the tape's own types.
  private def collect(node : ASTNode) : Nil
    node.accept Collector.new(self)
  end

  def reach(a_def : Def) : Nil
    return if internal?(a_def) || !@seen.add?(a_def.object_id)
    @defs << a_def
    collect a_def.body
  end

  class Collector < Visitor
    def initialize(@checker : TapeLayoutChecker)
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

  private def summarize(a_def : Def) : Summary
    effects = effects(a_def.body)
    params = Set(Int32).new
    ivars = Set(String).new
    effects.grows.each do |name|
      if name.starts_with?('@')
        ivars << name
      elsif index = a_def.args.index { |arg| arg.name == name }
        params << index
      end
    end
    Summary.new(params, ivars, effects.alloc ? effects.what : nil)
  end

  def summary(a_def : Def) : Summary?
    return nil if internal?(a_def)
    @summaries[a_def.object_id]? || Summary.empty
  end

  def effects(node : ASTNode) : Effects
    effects = Effects.new
    node.accept EffectCollector.new(self, effects)
    effects
  end

  class EffectCollector < Visitor
    def initialize(@checker : TapeLayoutChecker, @effects : Effects)
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      node.obj.try &.accept self
      node.args.each &.accept self
      node.named_args.try &.each &.value.accept(self)
      # A Tape.local block is on a tape of its own: what it puts there is
      # not on this one.
      node.block.try &.body.accept(self) unless tape_local?(node)

      receiver = node.obj
      if node.name == "new" && TapeLayoutChecker.container(node.type?)
        @effects.allocate(node, "a new #{TapeLayoutChecker.container(node.type?)}")
      elsif node.name == "build" && owned_by?(node, "TapeString")
        @effects.allocate(node, "TapeString.build")
      elsif receiver && (kind = TapeLayoutChecker.container(receiver.type?))
        grow(receiver, node) if GROWS[kind].includes?(node.name)
      else
        node.target_defs.try &.each do |a_def|
          summary = @checker.summary(a_def)
          next unless summary
          if what = summary.allocs
            @effects.allocate(node, "`#{node.name}` (#{what})")
          end
          summary.params.each do |index|
            arg = node.args[index]?
            arg ? grow(arg, node) : @effects.allocate(node, "`#{node.name}`")
          end
          summary.ivars.each do |ivar|
            if receiver.nil? || receiver.is_a?(Var) && receiver.name == "self"
              @effects.grows << ivar
            elsif receiver
              grow(receiver, node)
            end
          end
        end
      end
      false
    end

    private def owned_by?(node : Call, name : String) : Bool
      node.target_defs.try &.any? do |target|
        owner = target.owner
        owner.metaclass? && owner.instance_type.to_s == name
      end || false
    end

    private def tape_local?(node : Call) : Bool
      return false unless node.name == "local"
      node.target_defs.try &.any? do |target|
        owner = target.owner
        owner.metaclass? && owner.instance_type.to_s == "Tape"
      end || false
    end

    # A container named by a variable grows; any other is put on the tape.
    # A chain (`buffer << a << b`) of calls returning their receiver's type
    # names the receiver it started from.
    private def grow(container : ASTNode, call : Call) : Nil
      while container.is_a?(Call) && (inner = container.obj) && container.type? == inner.type?
        container = inner
      end
      case container
      when Var
        @effects.grows << container.name
      when InstanceVar
        @effects.grows << container.name
      else
        @effects.allocate(call, "a container that is not a variable growing")
      end
    end

    def visit(node : ProcLiteral)
      false # runs later, on its own
    end

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end

  private def check(node : ASTNode) : Nil
    node.accept LoopChecker.new(self)
  end

  def check_loop(body : ASTNode, params : Array(String)) : Nil
    effects = effects(body)
    locals = Set(String).new
    body.accept LocalCollector.new(locals)
    params.each { |name| locals.delete(name) }
    outer = effects.grows.reject { |name| locals.includes?(name) }
    return if outer.empty?
    if outer.size > 1
      body.raise "#{outer.map { |name| "`#{name}`" }.join(" and ")} all grow on the tape in this loop: only one container can be the tape's end, so each growth of the others copies them, slower than the GC heap.\n\n" + HINT
    end
    if alloc = effects.alloc
      alloc.raise "`#{outer.first}` grows on the tape in this loop, and #{effects.what} puts something else on the tape here: `#{outer.first}` is then never the tape's end, so each growth copies it, slower than the GC heap.\n\n" + HINT
    end
  end

  HINT = "Build a tree with TapeStream in document order, make the container at its final size (`TapeArray(T).new(count) { |i| ... }`), or keep this data on the GC heap. Why: TAPE_DESIGN.md, \"Layout\"."

  class LocalCollector < Visitor
    def initialize(@locals : Set(String))
    end

    def visit(node : Assign)
      if (target = node.target).is_a?(Var)
        @locals << target.name
      end
      true
    end

    # A nested block's parameters are its own: a writer a nested
    # `TapeString.build` yields is made inside the loop.
    def visit(node : Block)
      node.args.each { |arg| @locals << arg.name }
      true
    end

    def visit(node : ASTNode)
      true
    end
  end

  class LoopChecker < Visitor
    def initialize(@checker : TapeLayoutChecker)
    end

    def visit(node : While)
      @checker.check_loop(node.body, [] of String)
      true
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      if block = node.block
        @checker.check_loop(block.body, block.args.map(&.name))
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
