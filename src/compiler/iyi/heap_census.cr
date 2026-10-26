# Census rules (typed, after lowering; locations deduplicate specializations):
# class: heap-backed .new and allocate; ordinary tape classes are excluded.
# string: String construction/build/to_heap/interpolation; static literals
#   are data in the executable and never counted.
# array/hash: typed Array/Hash/Set construction and literal lowerings.
# closure: ProcLiteral whose typed Def has captures; noncapturing procs
#   are static function pointers. Bodies are reached even without a call.
# other: pointer_malloc/realloc and direct __iyi_* / new_object entries.
# Calls follow target_defs (all dispatch arms); Path follows constants.
# Defs are visited only when reached, not merely definition-site typed.
# Counts are potential source sites, not executed allocations: branches and
# shared constructor/buffer sites remain separate; allocator calls in foreign
# code and precompiled artifact bodies are opaque. Runtime-only owners are
# excluded, but program values in other iyi types (IO, Channel, etc.) remain.
# The same runtime-only owners are omitted by census and codegen hooks.
module Iyi::HeapPolicy
  def self.internal?(name : String) : Bool
    base = name.gsub(".class", "").gsub(":Module", "").split('(').first
    base.in?(%w(IyiHeap IyiRegion IyiRoots IyiMark IyiRuntimeLock
      IyiFiber IyiScheduler IyiSchedulerState IyiStackGuard IyiDefers
      IyiGroup IyiTask IyiWorkers
      IyiDeferNode IyiOnce RisHeap))
  end

  def self.allocator?(a_def : Def) : Bool
    a_def.name.in?(%w(__iyi_malloc64 __iyi_malloc_atomic64
      __iyi_realloc64 __iyi_new)) ||
      (a_def.owner?.to_s == "IyiHeap.class" &&
        a_def.name.in?(%w(alloc alloc_atomic realloc new_object)))
  end

  def self.internal_def?(a_def : Def) : Bool
    name = a_def.owner?.to_s
    file = a_def.location.try(&.original_filename)
    return true if a_def.name == "group" &&
                   file.try(&.ends_with?("/iyi/concurrency.iyi"))
    return true if a_def.name.starts_with?("__iyi_") &&
                   file.try(&.includes?("/src/iyi/"))
    allocator?(a_def) || internal?(name) || (name.in?(%w(IyiIO IyiIO.class)) &&
      a_def.name == "initialize")
  end
end

class Iyi::HeapCensus < Iyi::Visitor
  getter sites = Hash({String, Int32, Int32, String}, String).new
  @seen = Set(UInt64).new
  @constructor = false
  @initialized = Set(UInt64).new

  def initialize(@program : Program)
  end

  def run(node : ASTNode) : Nil
    node.accept self
  end

  def add(node : ASTNode, kind : String, detail : String) : Nil
    loc = node.location.try(&.expanded_location)
    return unless loc
    file = loc.original_filename
    return unless file
    key = {file, loc.line_number, loc.column_number, kind}
    if kind.in?("migration", "opaque", "exemption") && (old = @sites[key]?)
      detail = (old.split("; ") + [detail]).uniq.sort.join("; ")
    end
    @sites[key] = detail
  end

  def reach(a_def : Def) : Nil
    return unless @seen.add?(a_def.object_id)
    return if HeapPolicy.internal_def?(a_def)
    previous = @constructor
    @constructor = a_def.name == "new"
    a_def.body.accept self
    @constructor = previous
  end

  def initializers(type : Type?) : Nil
    return unless type.is_a?(ClassType) ||
                  type.is_a?(GenericClassInstanceType)
    return unless @initialized.add?(type.object_id)
    return if HeapPolicy.internal?(type.to_s)
    initializers(type.superclass)
    type.instance_vars_initializers.try &.each do |initializer|
      initializer.value.accept self
    end
  end

  def kind(type : Type?) : String
    name = type.to_s
    return "string" if name == "String"
    return "array" if name.starts_with?("Array(")
    return "hash" if name.starts_with?("Hash(") ||
                     name.starts_with?("Set(")
    "class"
  end

  # Audit categories overlap allocation kinds and never claim exact effects.
  def classify(node : Call, targets) : Nil
    if targets.nil? || targets.empty?
      add node, "opaque", "unknown target: #{node.name}"
      return
    end
    if targets.size > 1
      add node, "opaque", "virtual targets (all traversed): #{node.name}"
    end
    targets.each do |target|
      detail = "#{target.owner}##{target.name}"
      if target.is_a?(External)
        add node, "opaque", "FFI: #{detail}"
      elsif node.obj.try(&.type?).is_a?(ProcInstanceType) &&
            node.name == "call"
        add node, "opaque", "proc call: #{detail}"
      end
      if HeapPolicy.internal_def?(target) ||
         TapeRules.runtime?(@program, target.location) ||
         target.annotation(@program.tape_unsafe_annotation)
        add node, "exemption", "runtime/std exemption: #{detail}"
      end
      string_api = node.obj.try(&.type?).to_s.in?("String", "String.class") ||
                   node.args.any? { |arg| arg.type?.to_s == "String" }
      if node.name == "to_heap" ||
         (node.name == "to_s" && node.type?.to_s == "String") ||
         target.annotation(@program.tape_to_heap_annotation) || string_api
        reason = if node.name == "to_heap"
                   "to_heap"
                 elsif node.name == "to_s" && node.type?.to_s == "String"
                   "to_s to String"
                 elsif target.annotation(@program.tape_to_heap_annotation)
                   "@[TapeToHeap]"
                 else
                   "String API"
                 end
        add node, "migration", "#{reason}: #{detail}"
      end
    end
  end

  def visit(node : Call)
    if expanded = node.expanded
      expanded.accept self
      return false
    end
    targets = node.target_defs
    classify(node, targets)
    targets.try &.each do |target|
      if HeapPolicy.allocator?(target)
        add node, "other", "#{target.owner}##{target.name}"
        next
      end
      next if HeapPolicy.internal_def?(target)
      body = target.body
      type = node.type?
      initializers(type) if body.is_a?(Primitive) && body.name.in?("allocate", "program_allocate")
      if node.name.in?("new", "unsafe_build") && type && type.reference_like? &&
         !type.is_a?(PointerInstanceType) && !type.is_a?(ProcInstanceType)
        file = node.location.try(&.original_filename)
        stream = type.to_s == "IyiIO" && !@constructor &&
                 file.try(&.ends_with?("/iyi/io.iyi"))
        add node, kind(type), "#{type}.new" unless stream ||
                                                   TapeChecker.class_instance?(@program, type)
      elsif node.name.in?("to_heap", "build") && type &&
            type.reference_like?
        add node, kind(type), "#{target.owner}##{node.name}"
      elsif body.is_a?(Primitive) &&
            body.name.in?("allocate", "pointer_malloc", "pointer_realloc")
        next if body.name == "allocate" &&
                (@constructor || type.try(&.passed_by_value?) ||
                (type && TapeChecker.class_instance?(@program, type)))
        add node, body.name == "allocate" ? kind(type) : "other",
          "#{target.owner}##{node.name} (#{body.name})"
      elsif target.name.in?("__iyi_malloc64", "__iyi_malloc_atomic64",
              "__iyi_realloc64", "__iyi_new", "new_object")
        add node, "other", target.name
      end
      reach(target)
    end
    true
  end

  def visit(node : ProcLiteral)
    add(node, "closure", "captured proc context") if node.def.closure?
    reach(node.def)
    false
  end

  def visit(node : Block)
    if literal = node.fun_literal
      literal.accept self
      return false
    end
    true
  end

  def visit(node : ProcPointer)
    node.call.accept self
    true
  end

  def visit(node : Path)
    if constant = node.target_const
      constant.value.accept self if @seen.add?(constant.object_id)
    end
    true
  end

  def visit(node : FunDef)
    false
  end

  def visit(node : ClassDef)
    node.body.accept self
    false
  end

  def visit(node : ModuleDef)
    node.body.accept self
    false
  end

  def visit(node : ArrayLiteral)
    add node, "array", "Array literal"
    node.expanded.try &.accept(self)
    false
  end

  def visit(node : HashLiteral)
    add node, "hash", "Hash literal"
    node.expanded.try &.accept(self)
    false
  end

  def visit(node : StringInterpolation)
    add(node, "string", "heap interpolation") if node.type? == @program.string
    node.expanded.try &.accept(self)
    false
  end

  def visit(node : ClassVar)
    if initializer = node.var.initializer
      initializer.node.accept self if @seen.add?(initializer.object_id)
    end
    true
  end

  def visit(node : Def)
    false
  end

  def visit(node : ASTNode)
    if node.is_a?(ExpandableNode)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
    end
    true
  end
end
