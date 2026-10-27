# Resource identities may be borrowed, but a handoff consumes all aliases
# in the creating scope. Keep this separate from tape-storage lifetimes:
# a socket's state outlives the task, its right to use it does not.
class Iyi::ResourceChecker
  SAFE = "do this work in the receiving task, or send it a message"

  def initialize(@program : Program, @graph : TapeCallGraph)
  end

  def self.resource?(type : Type, seen = Set(Type).new) : Bool
    type = type.remove_typedef
    return false unless seen.add?(type)
    return false if {"IyiTask(", "RisInbox(", "RisWorkerTask("}.any? { |prefix| type.to_s.starts_with?(prefix) }
    return true if {"Std::Socket::IyiSocket", "Std::Io::PipeReader", "Std::Io::PipeWriter"}.includes?(type.to_s)
    case type
    when UnionType
      return type.union_types.any? { |t| resource?(t, seen) }
    when TupleInstanceType
      return type.tuple_types.any? { |t| resource?(t, seen) }
    when NamedTupleInstanceType
      return type.entries.any? { |e| resource?(e.type, seen) }
    when GenericClassInstanceType
      return true if type.type_vars.values.any? do |v|
        v.is_a?(Var) && v.type?.try { |t| resource?(t, seen) } == true
      end
    when ProcInstanceType, PointerInstanceType
      return false
    end
    if type.is_a?(InstanceVarContainer)
      return type.instance_vars.each_value.any? { |v| v.type?.try { |t| resource?(t, seen) } == true }
    end
    false
  end

  def run(node : ASTNode)
    node.accept Flow.new(@program, @graph)
    @graph.defs.each_value do |target|
      next if TapeRules.runtime?(@program, target.location)
      next if TapeRules.std?(target.location)
      target.body.accept Flow.new(@program, @graph, target)
    end
  end

  class Roots < Visitor
    getter names = Set(String).new
    getter resource_names = Set(String).new
    def visit(node : Var)
      @names << node.name
      @resource_names << node.name if node.type?.try { |t| ResourceChecker.resource?(t) }
      false
    end
    def visit(node : Def | ProcLiteral)
      false
    end
    def visit(node : ASTNode)
      true
    end
  end

  class Flow < Visitor
    @aliases = Hash(String, Set(String)).new
    @moved = Set(String).new
    @result_moved = Set(String).new
    @captured = Set(String).new
    @cleanup = false

    def initialize(@program : Program, @graph : TapeCallGraph, target : Def? = nil)
      target.try &.args.each do |arg|
        if arg.type?.try { |t| ResourceChecker.resource?(t) || (t.is_a?(ClassType) && !t.struct?) || t.is_a?(VirtualType) }
          @captured << arg.name
        end
      end
    end

    def roots(node : ASTNode) : Set(String)
      if node.is_a?(Call) && node.name == "[]" && (obj = node.obj) &&
         (index = node.args.first?).is_a?(NumberLiteral)
        return roots(obj).map { |r| "#{r}[#{index.value}]" }.to_set
      end
      collector = Roots.new
      node.accept collector
      result = Set(String).new
      collector.names.each do |name|
        if aliases = @aliases[name]?
          result.concat(aliases)
        elsif collector.resource_names.includes?(name)
          result << name
        end
      end
      result
    end

    def overlaps?(left : String, right : String) : Bool
      left == right || left.starts_with?("#{right}[") ||
        right.starts_with?("#{left}[")
    end

    def intersects?(left : Set(String), right : Set(String)) : Bool
      left.any? { |a| right.any? { |b| overlaps?(a, b) } }
    end

    def refuse(node : ASTNode, why : String) : NoReturn
      node.raise "#{why}; #{ResourceChecker::SAFE}"
    end

    def visit(node : Def | Macro)
      false
    end

    def visit(node : If)
      return false if node.iyi_definition_probe?
      node.cond.accept self
      node.then.accept self
      # A possible move remains consumed after either branch. This is
      # conservative when creation returns an error, never permissive.
      node.else.accept self
      false
    end

    def visit(node : Assign)
      node.value.accept self
      if target = node.target.as?(Var)
        source_roots = roots(node.value)
        if node.value.type?.try { |t| ResourceChecker.resource?(t) ||
             (!source_roots.empty? && ((t.is_a?(ClassType) && !t.struct?) || t.is_a?(VirtualType))) }
          @aliases[target.name] = source_roots
          @aliases[target.name] << target.name
          if node.value.is_a?(InstanceVar) || node.value.is_a?(ClassVar) ||
             node.value.is_a?(Global)
            @captured << target.name
          end
        else
          @aliases.delete(target.name)
        end
      else
        if node.value.type?.try { |t| ResourceChecker.resource?(t) }
          @captured.concat(roots(node.value))
        end
        node.target.accept self
      end
      false
    end

    def visit(node : TypeDeclaration)
      if value = node.value
        visit(Assign.new(node.var, value).at(node))
      end
      false
    end

    def visit(node : Var)
      if intersects?(roots(node), @moved)
        refuse(node, "resource `#{node.name}` was moved at task start")
      end
      if @cleanup && intersects?(roots(node), @result_moved)
        refuse(node, "resource `#{node.name}` was moved into the task result")
      end
      false
    end

    def visit(node : ExceptionHandler)
      node.body.accept self
      node.rescues.try &.each(&.accept(self))
      node.else.try &.accept self
      old = @cleanup
      @cleanup = node.iyi_defer?
      node.ensure.try &.accept self
      @cleanup = old
      false
    end

    def visit(node : ProcLiteral)
      if node.def.iyi_defer?
        old = @cleanup
        @cleanup = true
        node.def.body.accept self
        @cleanup = old
        return false
      end
      captures = Roots.new
      node.def.body.accept captures
      captures.names.each do |name|
        @captured.concat(@aliases[name]? || Set{name})
      end
      node.def.body.accept self
      false
    end

    def visit(node : Call)
      return false if @cleanup && node.name == "close"
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      unless TapeRules.runtime?(@program, node.location) || TapeRules.std?(node.location)
        if node.name == "__ris_task_result" && !node.resource_result?
          refuse(node, "task result placement is private; return the resource from the task")
        end
        if (node.obj.try(&.type?).try(&.to_s.starts_with?("IyiTask(")) &&
            {"finish", "retire", "new", "next_result", "next_result="}.includes?(node.name)) ||
           {"resource_results", "resource_results=", "result_tape", "result_tape=", "result_depth", "result_depth="}.includes?(node.name) ||
           node.name.starts_with?("__ris_resource") ||
           node.obj.try(&.type?).try(&.to_s.starts_with?("RisResources")) ||
           node.obj.try(&.type?).try(&.to_s.starts_with?("RisStagedResource")) ||
           node.obj.try(&.type?).try(&.to_s.starts_with?("RisResultOwner"))
          refuse(node, "resource ownership storage is private; use owns: or task.take")
        end
      end
      if {"new_inbox", "new_worker"}.includes?(node.name) &&
         node.args.first?.try(&.type?).try { |t| ResourceChecker.resource?(t.instance_type) }
        refuse(node, "resources are never messages")
      end
      if node.resource_result? && (value = node.args.first?)
        if value.type?.try { |t| ResourceChecker.resource?(t) } &&
           intersects?(roots(value), @captured)
          refuse(node, "a captured alias survives this resource result")
        end
      end
      resource_receiver = node.obj.try(&.type?).try { |t| ResourceChecker.resource?(t) }
      if resource_receiver && node.name == "fd" &&
         !TapeRules.runtime?(@program, node.location) && !TapeRules.std?(node.location) &&
         !node.location.try(&.original_filename).try { |file| @program.ris_resource_ffi_files.includes?(File.expand_path(file)) }
        refuse(node, "a resource descriptor cannot escape as a number")
      end
      if resource_receiver && node.name == "copy_to"
        refuse(node, "resources cannot copy_to")
      end
      owned = node.named_args.try(&.find { |a| a.name == "owns" }).try(&.value)
      unless owned
        @graph.targets(node).try &.each do |target|
          if index = target.args.index { |a| a.name == "owns" }
            owned ||= node.args[index]?
          end
        end
      end
      if owned && {"new_task", "new_worker"}.includes?(node.name)
        owned.accept self
        unless owned.is_a?(Var)
          refuse(owned, "owns: needs an exclusive named resource")
        end
        name = owned.as(Var).name
        identities = roots(owned)
        identities << name if identities.empty?
        @aliases.each do |other, set|
          next if other == name || other.starts_with?("%") || other.starts_with?("__temp_")
          if intersects?(set, identities)
            refuse(owned, "a surviving alias `#{other}` prevents exclusive ownership")
          end
        end
        if intersects?(identities, @captured)
          refuse(owned, "a captured alias survives this resource move")
        end
        body = node.block.try(&.body)
        body = node.block.try(&.fun_literal).as?(ProcLiteral).try(&.def.body) || body
        if body
          captures = Roots.new
          body.accept captures
          captures.names.each do |other|
            next if other == name
            if intersects?(@aliases[other]? || Set{other}, identities)
              refuse(node, "the receiving task captures resource alias `#{other}`")
            end
          end
          body.accept Flow.new(@program, @graph)
        end
        @aliases.each do |other, set|
          @moved << other if !other.starts_with?("%") && !other.starts_with?("__temp_") && intersects?(set, identities)
        end
        @moved.concat(identities)
        return false
      end
      if {"spawn", "new_task", "new_worker"}.includes?(node.name)
        body = node.block.try(&.fun_literal).as?(ProcLiteral).try(&.def.body) ||
          node.block.try(&.body)
        if body
          captures = Roots.new
          body.accept captures
          captures.names.each do |name|
            if identities = @aliases[name]?
              if node.name != "spawn"
                refuse(node, "a resource enters a task only through owns:")
              end
              @captured.concat(identities)
            end
          end
          body.accept Flow.new(@program, @graph)
          node.obj.try &.accept self
          node.args.each &.accept self
          return false
        end
      end
      node.obj.try &.accept self
      node.args.each &.accept self
      node.named_args.try &.each { |a| a.value.accept self }
      # Until borrowing summaries cover resource retention, an ordinary
      # helper given a resource may have retained an alias. An owns:
      # boundary below must not assume that a completed call erased it.
      unless node.resource_result?
        node.args.each do |arg|
          if arg.type?.try { |t| !t.metaclass? && ResourceChecker.resource?(t) }
            @captured.concat(roots(arg))
          end
        end
      end
      if node.resource_result? && (value = node.args.first?) &&
         value.type?.try { |t| ResourceChecker.resource?(t) }
        @result_moved.concat(roots(value))
      end
      node.block_arg.try &.accept self
      if literal = node.block.try(&.fun_literal).as?(ProcLiteral)
        literal.def.body.accept self
      else
        node.block.try(&.body.accept(self))
      end
      false
    end

    def visit(node : ASTNode)
      true
    end
  end
end
