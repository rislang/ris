require "../syntax/ast"
require "../syntax/transformer"
require "../types"

module Iyi
  class Program
    getter(cleanup_transformer : CleanupTransformer) do
      CleanupTransformer.new(self)
    end

    def cleanup(node, inside_def = false)
      transformer = self.cleanup_transformer
      transformer.inside_def! if inside_def
      transformer.top_level = node unless inside_def
      node = node.transform(transformer)
      puts node if ENV["AFTER"]? == "1"
      node
    end

    def cleanup_types
      transformer = self.cleanup_transformer

      after_inference_types.each do |type|
        cleanup_type type, transformer
      end

      self.class_var_initializers.each do |initializer|
        initializer.node = initializer.node.transform(transformer)
      end
    end

    def cleanup_type(type, transformer)
      case type
      when GenericClassInstanceType
        cleanup_single_type(type, transformer)
      when GenericClassType
        type.each_instantiated_type do |instance|
          cleanup_type instance, transformer
        end
      when ClassType
        cleanup_single_type(type, transformer)
      else
        # no need to clean up
      end
    end

    def cleanup_single_type(type, transformer)
      type.instance_vars_initializers.try &.each do |initializer|
        initializer.value = initializer.value.transform(transformer)
      end
    end

    def cleanup_files
      tempfiles.each do |tempfile|
        File.delete?(tempfile)
      end
    end
  end

  # This visitor runs at the end and does some simplifications to the resulting AST node.
  #
  # For example, it rewrites and `if true; 1; else; 2; end` to a single `1`. It does
  # so for other "always true conditions", such as `x.is_a?(Foo)` where `x` can only
  # be of type `Foo`. These simplifications are needed because the codegen would have no
  # idea on how to generate code for unreachable branches, because they have no type,
  # and for now the codegen only deals with typed nodes.
  class CleanupTransformer < Transformer
    @transformed : Set(Def)

    # The current method we are processing
    @current_def : Def?

    # iyi: the program's top-level code, where a captured top-level
    # variable's assignments are looked for (`check_thread_capture_assigned_once`).
    property top_level : ASTNode?

    def initialize(@program : Program)
      @transformed = Set(Def).new.compare_by_identity
      @exhaustiveness_checker = ExhaustivenessChecker.new(@program)
      @def_nest_count = 0
      @last_is_truthy = false
      @last_is_falsey = false
    end

    def inside_def!
      @def_nest_count += 1
    end

    def after_transform(node)
      case node
      when And, Or, If, RespondsTo, IsA, Assign
        # Nothing
      when BoolLiteral
        if node.value
          @last_is_truthy = true
        else
          @last_is_falsey = true
        end
      when Not
        if @last_is_truthy
          @last_is_falsey = true
          @last_is_truthy = false
        elsif @last_is_falsey
          @last_is_truthy = true
          @last_is_falsey = false
        else
          reset_last_status
        end
      when NilLiteral
        @last_is_falsey = true
      when Nop
        @last_is_falsey = true
      else
        if node.type?.try &.nil_type?
          @last_is_falsey = true
          @last_is_truthy = false
        else
          reset_last_status
        end
      end
    end

    def reset_last_status
      @last_is_truthy = false
      @last_is_falsey = false
    end

    def compute_last_truthiness(&)
      reset_last_status
      yield
      {@last_is_truthy, @last_is_falsey}
    end

    def transform(node : AnnotationDef)
      @program.check_call_to_deprecated_annotation node

      node
    end

    def transform(node : Def)
      node.hook_expansions.try &.map! &.transform self
      node
    end

    def transform(node : ClassDef)
      super

      # check superclass for deprecation if the node isn't deprecated
      if (type = node.type.lookup_type?(node.name)) && !type.annotation(@program.deprecated_annotation)
        if ((superclass = node.superclass).is_a?(Path) && (stype = superclass.type? || node.type.lookup_type?(superclass)))
          @program.check_deprecated_type(stype, superclass)
        end
      end

      node.hook_expansions.try &.map! &.transform self
      node
    end

    def transform(node : Include)
      node.hook_expansions.try &.map! &.transform self
      node
    end

    def transform(node : Extend)
      node.hook_expansions.try &.map! &.transform self
      node
    end

    def transform(node : Expressions)
      if exp = node.single_expression?
        return exp.transform(self)
      end

      exps = [] of ASTNode

      node.expressions.each_with_index do |exp, i|
        new_exp = exp.transform(self)

        # We collect the transformed expressions, recursively,
        # by flattening them. We stop collecting when there's
        # a NoReturn expression, next, break or return.
        break if flatten_collect(new_exp, exps)
      end

      node.expressions = exps
      # A scope wrapper assigns this list's value. Specialization can
      # make an early return unconditional, leaving its old last value
      # untyped. The shortened list now has the return's NoReturn type.
      if last = exps.last?
        node.bind_to(last) if last.no_returns?
      end
      node
    end

    def flatten_collect(exp, exps)
      exp = exp.single_expression
      if exp.is_a?(Expressions)
        exp.expressions.each do |subexp|
          return true if flatten_collect(subexp, exps)
        end
      else
        exps << exp
        if exp.is_a?(Break) || exp.is_a?(Next) || exp.is_a?(Return) || exp.no_returns?
          return true
        end
      end
      false
    end

    def transform(node : Case)
      @exhaustiveness_checker.check(node) if node.exhaustive?

      if expanded = node.expanded
        if node.exhaustive?
          replace_unreachable_if_needed(node, expanded)
        end

        return expanded.transform(self)
      end

      node
    end

    # If any of the types checked in `case` is an enum, it can happen that
    # the unreachable can be reached by doing `SomeEnum.new(some_value)`.
    # In that case we replace the Unreachable node with `raise "..."`.
    # In the future we should disallow creating such values.
    def replace_unreachable_if_needed(node, expanded)
      cond = node.cond
      return unless cond

      if cond.is_a?(TupleLiteral)
        return unless cond.elements.all?(&.type?) &&
                      cond.elements.any? { |element| has_enum_type?(element.type) }
      else
        cond_type = cond.type?
        return unless cond_type && has_enum_type?(cond_type)
      end

      an_if = find_unreachable_parent(expanded)
      unless an_if
        node.raise "BUG: expected to find Unreachable node"
      end

      an_if.else = build_raise("Unhandled case: enum value outside of defined enum members", node)
    end

    def has_enum_type?(type)
      if type.is_a?(UnionType)
        type.union_types.any?(EnumType)
      else
        type.is_a?(EnumType)
      end
    end

    def find_unreachable_parent(expanded)
      # An expanded case is either a series of if/else, or
      # a bunch of assignments and then a series of if/else.
      # The if/else chain always comes last.
      if expanded.is_a?(Expressions)
        expanded = expanded.expressions.last
      end

      while expanded.is_a?(If)
        if an_else = expanded.else
          if an_else.is_a?(Unreachable)
            return expanded
          else
            expanded = an_else
          end
        end
      end
      nil
    end

    def transform(node : StringInterpolation)
      # See if we can solve all the pieces to string literals.
      # If that's the case, we can replace the entire interpolation
      # with a single string literal.
      pieces = node.expressions.dup
      solve_string_interpolation_expressions(pieces)

      if pieces.all?(StringLiteral)
        string = pieces.join(&.as(StringLiteral).value)
        string_literal = StringLiteral.new(string).at(node)
        string_literal.type = @program.string
        return string_literal
      end

      if expanded = node.expanded
        return expanded.transform(self)
      end
      node
    end

    private def solve_string_interpolation_expressions(pieces : Array(ASTNode))
      pieces.each_with_index do |piece, i|
        replacement = solve_string_interpolation_expression(piece)
        next unless replacement

        pieces[i] = replacement
      end
    end

    private def solve_string_interpolation_expression(piece : ASTNode) : StringLiteral?
      if piece.is_a?(ExpandableNode)
        if expanded = piece.expanded
          return solve_string_interpolation_expression(expanded)
        end
      end

      case piece
      when Path
        if target_const = piece.target_const
          return solve_string_interpolation_expression(target_const.value)
        end
      when StringLiteral
        return piece
      end

      nil
    end

    def transform(node : ExpandableNode)
      if expanded = node.expanded
        return expanded.transform(self)
      end
      node
    end

    def transform(node : Assign)
      reset_last_status

      # A compiler temporary is exempt: a tape scope keeps its body's
      # value in one, and the body may be a Void lib call.
      target_name = node.target.as?(Var).try(&.name)
      if void_lib_call?(node.value) && !target_name.try(&.starts_with?("__temp_"))
        node.value.raise "assigning Void return value of lib fun call has no effect"
      end

      target = node.target

      # Ignore class var initializers
      if target.is_a?(ClassVar) && !target.type?
        return node
      end

      # This is the case of an instance variable initializer
      if @def_nest_count == 0 && target.is_a?(InstanceVar)
        return Nop.new
      end

      if target.is_a?(Path)
        const = target.target_const.not_nil!
        return node if !const.used? || const.cleaned_up?

        unless const.value.type?
          node.raise "can't infer type of constant #{const} (maybe the constant refers to itself?)"
        end

        if const.value.type.no_return?
          node.raise "constant #{const} has illegal type NoReturn"
        end
      end

      node.value = node.value.transform self

      unless node.value.type?
        return untyped_expression node
      end

      if target.is_a?(Path)
        const = const.not_nil!
        const.value = const.value.transform self
        const.cleaned_up = true
      end

      if target == node.value &&
         # This condition is because the interpreter will generate expressions
         # like `$~ = $~` in multidispatches, and that's fine.
         !(target.is_a?(Var) && target.special_var?)
        node.raise "expression has no effect"
      end

      # We don't want to transform constant assignments into no return
      unless node.target.is_a?(Path)
        if node.value.type?.try &.no_return?
          return node.value
        end
      end

      node
    end

    def transform(node : MultiAssign)
      expanded = node.expanded

      if node.values.size == 1 && expanded
        # the expanded node always starts with `temp = {{ node.values[0] }}`;
        # `temp_assign` is this whole Assign node and its deduced type is same
        # as the original RHS's type
        temp_assign = expanded.as(Expressions).expressions.first
        type = temp_assign.type?

        # if the Assign node's RHS is untyped, this and all following
        # assignments are unreachable
        unless type
          return untyped_expression node
        end

        target_count = node.targets.size
        has_strict_multi_assign = @program.has_flag?("strict_multi_assign")

        # disallows `a, *b, c = {0 => "x", 1 => "y", 2 => "z"}`, as `Hash` is
        # not `Indexable`
        # also disallows `a, b, c = ...` if the strict flag is set
        if node.targets.any?(Splat) || has_strict_multi_assign
          unless type.implements?(@program.indexable)
            node.values.first.raise "right-hand side of one-to-many assignment must be an Indexable, not #{type}"
          end
        end

        if has_strict_multi_assign
          case type
          when UnionType
            sizes = type.union_types.map { |union_type| constant_size(union_type) }
            if sizes.none? &.in?(target_count, nil)
              node.values.first.raise "cannot assign #{type} to #{target_count} targets"
            end
          else
            if size = constant_size(type)
              unless size == target_count
                node.values.first.raise "cannot assign #{type} to #{target_count} targets"
              end
            end
          end
        end
      end

      if expanded
        return expanded.transform self
      end

      node
    end

    private def constant_size(type)
      case type
      when TupleInstanceType
        type.size
      end
    end

    def transform(node : Path)
      if const = node.target_const
        @program.check_deprecated_constant(const, node)

        # Some constants might not have been cleaned up at this point because
        # they don't have an explicit `Assign` node. One example is regex
        # literals: a constant is created for them, but there's no `Assign` node.
        if const.used? && !const.cleaned_up?
          const.value = const.value.transform self
          const.cleaned_up = true
        end
      elsif type = node.target_type
        @program.check_deprecated_type(type, node)
      end

      node
    end

    def transform(node : Generic)
      transform_many node.type_vars

      node
    end

    private def void_lib_call?(node)
      return false unless node.is_a?(Call)

      obj = node.obj
      return false unless obj.is_a?(Path)

      type = obj.type?
      return false unless type.is_a?(LibType)

      !!node.type?.try &.nil_type?
    end

    def transform(node : Global)
      if expanded = node.expanded
        return expanded.transform self
      end

      node
    end

    def transform(node : Call)
      if expanded = node.expanded
        return expanded.transform self
      end

      if (targets = node.target_defs) && targets.size == 1 &&
         targets[0].name == "spawn" && targets[0].owner.to_s == "IyiGroup"
        if (joined = node.block.try(&.fun_literal)).is_a?(ProcLiteral)
          @joined_task_blocks << joined.def
          @joined_task_calls[joined.def] = node
        end
        if (joined = node.block_arg).is_a?(ProcLiteral)
          @joined_task_blocks << joined.def
          @joined_task_calls[joined.def] = node
        end
      end

      # Need to transform these manually because node.block doesn't
      # need to be transformed if it has a fun_literal
      # ~~~
      if node_obj = node.obj
        node.obj = node_obj.transform(self)
      end
      transform_many node.args

      if (node_block = node.block) && !node_block.fun_literal
        # TODO: if the block isn't used in any of the target defs we could
        # avoid transforming it, because it probably isn't typed **at all**
        scope_mark = ris_scope_mark(node)
        if scope_mark
          @ris_scope_marks << scope_mark
          @ris_scope_names << (scope_mark == :tape ? AssignedNames.collect(node_block.body) : nil)
        end
        node.block = node_block.transform(self)
        if scope_mark
          @ris_scope_marks.pop
          @ris_scope_names.pop
        end
      end

      if node_block_arg = node.block_arg
        node.block_arg = node_block_arg.transform(self)
      end

      if named_args = node.named_args
        named_args.map! { |named_arg| named_arg.transform(self).as(NamedArgument) }
      end
      # ~~~

      node.args.each do |arg|
        if void_lib_call?(arg)
          arg.raise "passing Void return value of lib fun call has no effect"
        end
      end

      named_args.try &.each do |arg|
        if void_lib_call?(arg)
          arg.raise "passing Void return value of lib fun call has no effect"
        end
      end

      obj = node.obj
      obj_type = obj.try &.type?
      block = node.block

      # It might happen that a call was made on a module or an abstract class
      # and we don't know the type because there are no including classes or subclasses.
      # In that case, turn this into an untyped expression.
      if !node.type? && obj && obj_type && (obj_type.module? || obj_type.abstract? || obj_type.is_a?(GenericType))
        return untyped_expression(node, "`#{node}` has no type")
      end

      if block && (fun_literal = block.fun_literal)
        block.fun_literal = fun_literal.transform(self)
      end

      # Check if we have an untyped expression in this call. Replace it with raise.
      if (obj && !obj_type)
        return untyped_expression(node, "`#{obj}` has no type")
      end

      node.args.each do |arg|
        unless arg.type?
          return untyped_expression(node, "`#{arg}` has no type")
        end
      end

      node.named_args.try &.each do |named_arg|
        unless named_arg.value.type?
          return untyped_expression(node, "`#{named_arg}` has no type")
        end
      end

      # Check if the block has its type frozen and it doesn't match the current type
      if block && (freeze_type = block.freeze_type) && (block_type = block.type?)
        unless block_type.implements?(freeze_type)
          freeze_type = freeze_type.base_type if freeze_type.is_a?(VirtualType)
          node.raise "expected block to return #{freeze_type}, not #{block_type}"
        end
      end

      # If any expression is no-return, replace the call with its expressions up to
      # the one that no returns.
      if (obj.try &.type?.try &.no_return?) || (node.args.any? &.type?.try &.no_return?) ||
         (node.named_args.try &.any? &.value.type?.try &.no_return?)
        call_exps = [] of ASTNode
        call_exps << obj if obj
        unless obj.try &.type?.try &.no_return?
          node.args.each do |arg|
            call_exps << arg
            break if arg.type?.try &.no_return?
          end
          node.named_args.try &.each do |named_arg|
            call_exps << named_arg.value
            break if named_arg.value.type?.try &.no_return?
          end
        end
        exps = Expressions.new(call_exps)
        exps.set_type(call_exps.last.type?) unless call_exps.empty?
        return exps
      end

      if target_defs = node.target_defs
        if target_defs.size == 1
          if target_defs[0].is_a?(External)
            check_args_are_not_closure node, "can't send closure to C function"
          elsif obj_type && obj_type.extern? && node.name.ends_with?('=')
            check_args_are_not_closure node, "can't set closure as C #{obj_type.type_desc} member"
          end
          target = target_defs[0]
          if target.name == "spawn" && target.owner.to_s == "IyiGroup" &&
             (joined_block = node.block) &&
             (joined_proc = joined_block.fun_literal).is_a?(ProcLiteral)
            @joined_task_blocks << joined_proc.def
            @joined_task_calls[joined_proc.def] = node
          end
          check_share_boundary(node, target_defs[0])
        end
        if (block = node.block) && (fun_literal = block.fun_literal).is_a?(ProcLiteral)
          check_tape_captures(fun_literal.def)
        end

        current_def = @current_def

        target_defs.each do |target_def|
          if @transformed.add?(target_def)
            node.bubbling_exception do
              @current_def = target_def
              @def_nest_count += 1
              saved_marks = @ris_scope_marks
              saved_names = @ris_scope_names
              @ris_scope_marks = [] of Symbol
              @ris_scope_names = [] of Set(String)?
              target_def.body = target_def.body.transform(self)
              @ris_scope_marks = saved_marks
              @ris_scope_names = saved_names
              @def_nest_count -= 1
              @current_def = current_def
            end
          end

          # If the current call targets a method that raises, the method
          # where the call happens also raises.
          current_def.raises = true if current_def && target_def.raises?
        end

        if node.target_defs.not_nil!.empty?
          exps = [] of ASTNode
          if obj = node.obj
            exps.push obj
          end
          node.args.each { |arg| exps.push arg }
          call_exps = Expressions.from exps
          call_exps.set_type(exps.last.type?) unless exps.empty?
          return call_exps
        end
      end

      node.replace_splats

      # Convert named arguments to regular arguments, because intermediate
      # defs with the needed number of arguments are already defined.
      if named_args = node.named_args
        named_args.each do |named_arg|
          node.args << named_arg.value
        end
        node.named_args = nil
      end

      # Check deprecations last, after the arguments have been flattened.
      unless @current_def.try(&.annotation(@program.deprecated_annotation))
        @program.check_call_to_deprecated_method(node)
      end

      node
    end

    # ris: SPEC 3.2 for a task's captures. A value made in an
    # explicit `tape` block ends with it; a task spawned there into a group
    # opened outside it may run after, so it may not capture a local the
    # block assigns. A group opened inside the block joins before it ends.
    private def check_tape_block_spawn(a_def : Def, vars) : Nil
      inside = [] of Set(String)
      @ris_scope_marks.each_with_index.to_a.reverse_each do |(mark, index)|
        break if mark == :group
        if mark == :tape && (names = @ris_scope_names[index]?)
          inside << names
        end
      end
      return if inside.empty? || task_closure_unsafe_scope?
      ClosuredVarsCollector.collect(a_def).each do |captured|
        next unless captured.is_a?(Var)
        meta = vars.try &.[captured.name]?
        next unless meta
        next if meta.belongs_to?(a_def)
        next unless inside.any? &.includes?(captured.name)
        captured.raise "this task captures `#{captured.name}`, set inside " \
                       "a `tape` block that ends and frees it before the " \
                       "task's group joins: open the `group` inside the " \
                       "`tape` block, or set `#{captured.name}` before the " \
                       "`tape` block (copy_to(owner) for its tape value)"
      end
    end

    # The local names a `tape` block's body assigns, its nested blocks
    # included: what the block makes may be bound to any of them.
    class AssignedNames < Visitor
      getter names = Set(String).new

      def self.collect(node : ASTNode) : Set(String)
        visitor = new
        node.accept visitor
        visitor.names
      end

      def visit(node : Assign)
        target = node.target
        @names << target.name if target.is_a?(Var)
        true
      end

      def visit(node : MultiAssign)
        node.targets.each { |t| @names << t.name if t.is_a?(Var) }
        true
      end

      def visit(node : OpAssign)
        target = node.target
        @names << target.name if target.is_a?(Var)
        true
      end

      def visit(node : Block)
        node.args.each { |arg| @names << arg.name }
        true
      end

      def visit(node : ASTNode)
        true
      end
    end

    # PROTOTYPE (ris, step B): a block that becomes a proc - `-> { }`, the
    # block `spawn` or a callback keeps - may run after the tape block it
    # was made in has ended, so it may not capture a tape value.
    @joined_task_blocks = Set(Def).new
    @joined_task_calls = Hash(Def, Call).new

    # ris: the blocks a call's block is lexically inside in this def:
    # :group for `group`, :tape for `tape`.
    @ris_scope_marks = [] of Symbol
    @ris_scope_names = [] of Set(String)?

    private def ris_scope_mark(node : Call) : Symbol?
      return nil if node.obj
      case node.name
      when "group"      then :group
      when "tape"       then :tape
      end
    end

    def check_tape_captures(a_def : Def)
      # A lowered defer runs before its owning tape is released.
      return if a_def.iyi_defer?
      return unless a_def.closure?
      vars = a_def.vars
      if @joined_task_blocks.includes?(a_def) && @program.has_flag?("ris_no_gc")
        check_tape_block_spawn(a_def, vars)
      end
      ClosuredVarsCollector.collect(a_def).each do |captured|
        next unless captured.is_a?(Var)
        meta = vars.try &.[captured.name]?
        next unless meta
        next if meta.belongs_to?(a_def)
        type = meta.type?
        next unless type
        if found = Iyi::TapeChecker.tape_in(@program, type)
          # A group joins before its caller's tape ends. Immutable text
          # can be borrowed; Share checks still forbid reassigned captures.
          next if @joined_task_blocks.includes?(a_def) && type == @program.string
          # std's reviewed exceptions name the owner that joins the task
          # before the captured value's tape ends.
          next if @joined_task_blocks.includes?(a_def) && task_closure_unsafe_scope?
          if type.to_s.in?("Std::Socket::IyiSocket",
               "Std::Io::PipeReader", "Std::Io::PipeWriter") &&
             (call = @joined_task_calls[a_def]?) &&
             handed_off?(call, captured, meta)
            next
          end
          captured.raise "this block becomes a proc, which may run after " \
                         "the tape block that made `#{captured.name} : #{type}` has " \
                         "ended, and #{found} is a tape type: pass what the block " \
                         "needs as owned data (copy_to(owner)), " \
                         "build tape values " \
                         "inside the spawned task, or call the block inside " \
                         "the scope without keeping it"
        end
      end
    end

    # iyi: a block that crosses a `Share` boundary may capture only `Share`
    # values (iyi SPEC III.4.4). Three blocks cross one. `IyiThread.start { }`'s
    # runs on another thread (III.4.11), and `IyiGroup#spawn_parallel { }`'s
    # may (III.4.13): a parallel task is started by whichever pool worker is
    # free, so it is held to exactly what a thread's block is. And the block
    # a method of an owning type runs (`@[Share(owns: true)]`, `Mutex#lock`
    # and the rest) reaches the value the type keeps behind its lock: what
    # the block captures would come within reach of that value, so it must
    # be Share, and what the call answers leaves the lock, so it must be
    # Share too. That is what lets `Mutex(Array(Int32))` be Share although
    # `Array(Int32)` is not: nothing but these blocks reaches the array.
    #
    # The block became a proc when the call was typed, and the proc's def
    # knows which of the enclosing variables it closed over; each one's type
    # is asked, and `self` too when the block reached an instance variable
    # or called one of self's methods receiverless.
    def check_share_boundary(node : Call, target_def : Def)
      owner = target_def.owner
      thread = if target_def.name == "start" && owner.metaclass? && owner.instance_type.to_s == "IyiThread"
                 THREAD_BOUNDARY
               elsif target_def.name == "spawn_parallel" && !owner.metaclass? && owner.to_s == "IyiGroup"
                 PARALLEL_BOUNDARY
               elsif target_def.name == "spawn" && !owner.metaclass? && owner.to_s == "IyiGroup" && !task_closure_unsafe_scope?
                 LOCAL_BOUNDARY
               end
      owning = thread ? nil : share_owning_type(owner)
      return unless thread || owning
      block = node.block
      return unless block
      # Inline blocks cross the same result boundary as kept blocks.
      # Only capture inspection below needs a proc's definition.
      if owning && !owner.metaclass? && (answer = node.type?)
        if why = Iyi::Share.reason(answer)
          node.raise "#{owning}##{target_def.name} answers `#{answer}`, " \
                     "which is not Share: #{why}; " \
                     "answer Share scalar data or use `lock`, which answers nil"
        end
      end
      fun_literal = block.fun_literal
      return unless fun_literal.is_a?(ProcLiteral)
      a_def = fun_literal.def

      if owning
        name = owning.to_s.split("::").last.split('(').first
        subject = if owner.metaclass?
                    "the block #{name}.#{target_def.name} makes the #{name}'s value in"
                  else
                    "the block #{name}##{target_def.name} runs behind the #{name}'s lock"
                  end
        consequence = "whatever the block can reach, the value behind the lock can reach, and the lock no longer guards it (iyi SPEC III.4.4)"
        check_share_constants(a_def, subject, consequence)
        check_share_class_var_types(a_def, subject, consequence)
      elsif thread
        subject = thread.subject
        consequence = thread.consequence
        check_thread_constants_share(a_def, thread)
        check_thread_class_vars_share(a_def, thread)
        check_reached_state_writes(a_def, thread)
      end
      return unless a_def.closure?

      vars = a_def.vars
      seen = Set(String).new
      captures_self = false
      ClosuredVarsCollector.collect(a_def).each do |captured|
        case captured
        when InstanceVar
          # An instance variable read inside the block is `self`, captured.
          captures_self = true
        when Var
          if captured.name == "self"
            captures_self = true
            next
          end
          next unless seen.add?(captured.name)
          meta = vars.try &.[captured.name]?
          next unless meta
          next if meta.belongs_to?(a_def)
          type = meta.type?
          next unless type
          if (why = Iyi::Share.reason(type)) && !(thread == LOCAL_BOUNDARY && handed_off?(node, captured, meta))
            captured.raise "#{subject} captures `#{captured.name} : #{type}`, which is not Share: #{why}#{owning || thread == LOCAL_BOUNDARY ? "; " : " "}#{consequence}"
          end
          # A block behind a lock runs in the task that called it, so a
          # local it assigns is that task's alone; only a thread's block
          # and a parallel task's share the cell.
          check_thread_capture_assigned_once(node, captured, meta, a_def, thread) if thread
        end
      end

      # `bump` written for `self.bump` reaches self as `@n` does, and the
      # closure's variables do not list it: a block calling `bump` twenty
      # million times beside its starter's twenty million compiled and
      # counted 28936626 of 40000000, where `@n += 1` in the block was
      # refused. A receiverless call to a method that takes self is a
      # capture of self.
      if captures_self || ReceiverlessSelfCalls.any?(a_def.body)
        if self_type = @current_def.try(&.owner)
          unless self_type.is_a?(Program) || self_type.metaclass?
            if why = Iyi::Share.reason(self_type)
              block.raise "#{subject} captures `self : #{self_type}`, which is not Share: #{why}#{owning || thread == LOCAL_BOUNDARY ? "; " : " "}#{consequence}"
            end
          end
        end
      end
    end

    # The owning type a method belongs to, its class method or its
    # instance's: `Mutex` for `Mutex.new` and for `Mutex(Array(Int32))#lock`.
    private def share_owning_type(owner : Type) : Type?
      type = owner.metaclass? ? owner.instance_type : owner
      type = type.generic_type.as(Type) if type.is_a?(GenericClassInstanceType)
      type.iyi_share_owns? ? type : nil
    end

    # A constant or a class variable a block behind a lock names is a way
    # out of it and a way in, as a captured variable is: its type must be
    # Share. Whether another thread writes the cell is the thread check's
    # question, not this one's.
    def check_share_constants(a_def : Def, subject : String, consequence : String) : Nil
      named = NamedConstants.new
      a_def.body.accept named
      named.paths.each do |path, type|
        if why = Iyi::Share.reason(type)
          path.raise "#{subject} names the constant `#{path} : #{type}`, which is not Share: #{why}; #{consequence}"
        end
      end
    end

    def check_share_class_var_types(a_def : Def, subject : String, consequence : String) : Nil
      named = NamedClassVars.new
      a_def.body.accept named
      named.vars.each do |class_var, var|
        type = var.type?
        next unless type
        if why = Iyi::Share.reason(type)
          class_var.raise "#{subject} names the class variable `#{class_var.name} : #{type}`, which is not Share: #{why}; #{consequence}"
        end
      end
    end

    # iyi: who the two parties to a shared cell are, in the sentences the
    # thread check and the parallel task's check refuse one with.
    record ShareBoundary, subject : String, local_owner : String, pair : String, again : String, after : String,
      consequence : String = "(iyi SPEC III.4.4)",
      race : String = "a data race (iyi SPEC III.4.4)",
      cure : String = "keep the value in an `Atomic`, or in one owner task that the others send RisBoard messages to"

    # ris: a local task runs on its spawner's thread, but it is still a
    # task of its own (SPEC 5.1): it captures only Share values,
    # never a mutable borrow of its spawner's state or a resource.
    LOCAL_BOUNDARY = ShareBoundary.new(
      subject: "the block spawn runs as another task",
      local_owner: "a local of the code that spawned the task, so the task and its spawner",
      pair: "the task and the code that spawned it",
      again: "spawns the task again",
      after: "the task was spawned",
      consequence: "a task captures only Share values or a copy it makes itself; pass a Copyable value through RisBoard (post/take), or open the resource inside the task (SPEC 5.1)",
      race: "a mutable borrow across tasks (SPEC 5.1)",
      cure: "send the value through RisBoard (post/take), or answer it from the task's `value`")

    # ris: a value the spawner hands to a local task and never reads again
    # is the task's alone, as a resource opened in it would be (SPEC
    # 5.1): `g.spawn { serve(client) }` with no later `client`. Spawned in a
    # loop or a block that runs again, the cell is the next one's too.
    private def handed_off?(start : Call, captured : Var, meta : MetaVar) : Bool
      scope = meta.context
      body, vars = case scope
                   when Def, Block then {scope.body, scope.vars}
                   else                 {@top_level, @program.vars}
                   end
      walk = CaptureAssignments.new(@program, meta, start, vars)
      body.try &.accept(walk)
      return false unless walk.found_start?
      if copy = walk.aliases.first?
        name = copy.target.to_s == captured.name ? copy.value.to_s : copy.target.to_s
        copy.raise "`#{copy.target} = #{copy.value}` keeps a second name for the value handed to the task spawned at line #{start.location.try(&.line_number)}: the task owns it (SPEC 5.1), so `#{name}` would reach it while the task runs. Use `#{captured.name}` alone, or open another resource for `#{name}`"
      end
      walk.passed.each do |call, index|
        next unless via = KeptArgument.new(@program).keeps?(call, index)
        call.raise "`#{call}` may keep `#{captured.name}` (through `#{via}`) before it is handed to the task spawned at line #{start.location.try(&.line_number)}: the task owns it (SPEC 5.1), so what the call kept would reach it while the task runs. Make the call inside the task, or give the call another resource of its own"
      end
      if use = walk.uses.first?
        use.raise "`#{captured.name}` is read here, after it was handed to the task spawned at line #{start.location.try(&.line_number)}: the task owns it now (SPEC 5.1). Use it only inside the task, or hand the task a copy"
      end
      # Only `group do |g|` runs its block once; any other block or loop
      # may spawn again with the same cell.
      walk.start_regions.all? do |region|
        region.is_a?(Block) && region.args.size == 1 &&
          region.args[0].type?.to_s == "IyiGroup"
      end
    end

    # A def marked `@[TaskClosureUnsafe("…")]` names the owner that joins
    # its tasks; its spawns are std's reviewed exceptions to 5.1.
    private def task_closure_unsafe_scope? : Bool
      !!@current_def.try(&.annotation(@program.task_closure_unsafe_annotation))
    end

    THREAD_BOUNDARY = ShareBoundary.new(
      subject: "the block IyiThread.start runs on another thread",
      local_owner: "a local of the code that started the thread, so the two threads",
      pair: "the thread and the code that started it",
      again: "starts the thread again",
      after: "the thread has started")

    PARALLEL_BOUNDARY = ShareBoundary.new(
      subject: "the block spawn_parallel runs on another thread",
      local_owner: "a local of the code that spawned the task, so the task and its spawner",
      pair: "the task and the code that spawned it",
      again: "spawns the task again",
      after: "the task was spawned")

    # iyi: a captured local is one cell on the heap, and the thread and the
    # code that started it both reach that cell. A Share type makes the
    # value safe to read from two threads, not the cell safe to write: `count
    # = 0`, a thread adding to `count` two million times and its starter
    # doing the same compiled, and printed 2684265, 2355445 and 4000000 on
    # three runs. The cell is safe when nothing assigns it once the thread
    # can read it: not the thread's block, nothing after the start, nothing
    # in a loop or a block that starts the thread again, and no block or
    # proc that may run later. A variable the typer never saw assigned
    # after a closure took it, in a `while`, or from a block or a proc is
    # not `mutably_closured`, and needs no walk. A parallel task's block is
    # the same cell on two threads, and asked the same.
    def check_thread_capture_assigned_once(start : Call, captured : Var, meta : MetaVar, a_def : Def, boundary : ShareBoundary)
      return unless meta.mutably_closured?

      name = captured.name
      inside = CaptureAssignments.new(@program, meta, nil, a_def.vars)
      a_def.body.accept inside
      if first = inside.assigns.first?
        first[0].raise "#{boundary.subject} assigns `#{name}`, #{boundary.local_owner} share one mutable cell: #{boundary.race}. #{boundary.cure[0].upcase}#{boundary.cure[1..]}"
      end

      scope = meta.context
      body, vars = case scope
                   when Def, Block then {scope.body, scope.vars}
                   else                 {@top_level, @program.vars}
                   end
      outside = CaptureAssignments.new(@program, meta, start, vars)
      body.try &.accept(outside)
      line = start.location.try(&.line_number)
      advice = "so #{boundary.pair} share one mutable cell: #{boundary.race}. " \
               "Capture a local that is assigned once (a block's own locals are new on every call), " \
               "or #{boundary.cure}"
      # Not found, or found assigned nowhere: the walk does not know this
      # scope, and the typer's answer stands.
      unless outside.found_start? && !outside.assigns.empty?
        captured.raise "#{boundary.subject} captures `#{name}`, which is assigned again after the capture, or inside a loop or a block, #{advice}"
      end

      outside.assigns.each do |assign, regions, after|
        why =
          if regions.any? { |region| outside.start_regions.any?(&.same?(region)) }
            "in a loop or a block that #{boundary.again}"
          elsif regions.any? { |region| region.is_a?(ProcLiteral) || (region.is_a?(Block) && region.fun_literal) }
            "in a block or a proc that may run after #{boundary.after}"
          elsif after
            "after #{boundary.after}"
          end
        next unless why
        assign.raise "`#{name}` is assigned here, #{why}, and #{boundary.subject} (line #{line}) captures it, #{advice}"
      end
    end

    # iyi: a constant is module-level state the block names in its own text,
    # so it is no variable the closure lists, and a block reading only
    # constants is no closure at all: `COUNTS = [0]` with `COUNTS[0] += 1`
    # run a million times in the block and a million by its starter
    # compiled and printed 1061337 (iyi SPEC III.4.5). Each constant the
    # block, its inlined blocks and its procs name is asked what a captured
    # variable is. One that a method the block calls reads is reached
    # through the call, and is not seen here.
    def check_thread_constants_share(a_def : Def, boundary : ShareBoundary) : Nil
      named = NamedConstants.new
      a_def.body.accept named
      named.paths.each do |path, type|
        # Program roots are frozen by TapeProgramChecker in threaded code.
        next if TapeChecker.tape_in(@program, type)
        if why = Iyi::Share.reason(type)
          path.raise "#{boundary.subject} names the constant `#{path} : #{type}`, which is not Share: #{why} (iyi SPEC III.4.5)"
        end
      end
    end

    # ris: SPEC 5.1 checks reached program state transitively. A
    # method the task calls, or one that method calls, may write a class
    # variable or change a constant's value: a cell the task and its
    # spawner (or two tasks) share although the block's text names
    # neither. std's and the runtime's methods keep their own rules.
    def check_reached_state_writes(a_def : Def, boundary : ShareBoundary) : Nil
      walk = ReachedStateWrites.new(@program, boundary == LOCAL_BOUNDARY,
        ->{ all_proc_literals })
      a_def.body.accept walk
      return unless found = walk.found
      node, state, via = found
      where = if via && via.name == "->"
                "in a proc the task calls (made at line #{via.location.try(&.line_number)})"
              elsif via
                "through `#{via.name}`, which the task calls"
              else
                "in the task's block"
              end
      node.raise "#{boundary.subject} changes `#{state}` #{where}: program " \
                 "state a task reaches has no writer after its initializer " \
                 "(SPEC 5.1). Keep the state in one task and send " \
                 "changes through RisBoard (post/take), answer it from the " \
                 "task's `value`, or keep it in an `Atomic`"
    end

    @all_proc_literals : Array(ProcLiteral)?

    # Every proc the program makes, in its top level and its typed defs: a
    # proc a task calls may have been made anywhere and kept in program
    # state (a class variable of handlers), so a call of one is taken to
    # run each proc of its type.
    private def all_proc_literals : Array(ProcLiteral)
      @all_proc_literals ||= begin
        found = [] of ProcLiteral
        collector = ProcLiteralCollector.new(found)
        @top_level.try &.accept collector
        seen = Set(UInt64).new
        collect_proc_literals(@program, collector, seen)
        @program.file_modules.each_value do |file_module|
          collect_proc_literals(file_module, collector, seen)
        end
        found
      end
    end

    private def collect_proc_literals(type : Type, collector : ProcLiteralCollector,
                                      seen : Set(UInt64)) : Nil
      return unless seen.add?(type.object_id)
      if type.is_a?(NamedType) || type.is_a?(Program) || type.is_a?(FileModule)
        type.types?.try &.each_value { |inner| collect_proc_literals(inner, collector, seen) }
      end
      if type.is_a?(GenericType)
        type.each_instantiated_type { |instance| collect_proc_literals(instance, collector, seen) }
      end
      collect_proc_literals(type.metaclass, collector, seen) if type.metaclass != type
      if type.is_a?(DefInstanceContainer)
        type.def_instances.each_value do |typed_def|
          next if TapeRules.runtime?(@program, typed_def.location) || TapeRules.std?(typed_def.location)
          typed_def.body.accept collector
        end
      end
    end

    class ProcLiteralCollector < Visitor
      @seen = Set(UInt64).new

      def initialize(@found : Array(ProcLiteral))
      end

      def visit(node : ProcLiteral)
        @found << node if @seen.add?(node.object_id)
        node.def.body.accept self
        false
      end

      def visit(node : Block)
        if (literal = node.fun_literal).is_a?(ProcLiteral)
          @found << literal if @seen.add?(literal.object_id)
        end
        true
      end

      def visit(node : Call)
        node.expanded.try &.accept self
        true
      end

      def visit(node : Def | Macro)
        false
      end

      def visit(node : ASTNode)
        true
      end
    end

    class ReachedStateWrites < Visitor
      MUTATORS = {"<<", "[]=", "push", "pop", "shift", "unshift", "clear",
                  "delete", "delete_at", "concat", "insert", "fill",
                  "replace", "update", "put", "add", "truncate"}
      getter found : {ASTNode, String, Def?}?
      @seen = Set(UInt64).new
      @via : Def? = nil

      # A local task runs on its spawner's thread: only a container's
      # change (not Share) races there. Across threads every write does,
      # except tape state, which TapeProgramChecker refuses on its own.
      def initialize(@program : Program, @local : Bool,
                     @procs : Proc(Array(ProcLiteral)))
      end

      # A proc made in what the task reaches runs when it is called: its
      # body is walked as a called def's is.
      def visit(node : ProcLiteral)
        return false if @found
        walk_proc(node)
        false
      end

      private def walk_proc(literal : ProcLiteral) : Nil
        return unless @seen.add?(literal.object_id)
        literal.def.body.accept self
      end

      def visit(node : Assign | OpAssign)
        target = node.target
        if target.is_a?(ClassVar) && !thread_local?(target) &&
           counted?(target.var?.try(&.type?))
          note(node, target.name)
        end
        true
      end

      # A method called on Share state (an Atomic's `add`) is its own
      # synchronization; an assignment across threads is not.
      private def counted?(type : Type?, call = false) : Bool
        return false unless type
        return false if !@local && Iyi::TapeChecker.tape_in(@program, type)
        return true unless @local || call
        !!Iyi::Share.reason(type)
      end

      def visit(node : Call)
        return false if @found
        if (obj = node.obj) && mutator?(node.name)
          if obj.is_a?(ClassVar) && !thread_local?(obj) &&
             counted?(obj.var?.try(&.type?), call: true)
            note(node, obj.name)
          elsif obj.is_a?(Path) && obj.target_const && counted?(obj.type?, call: true)
            note(node, obj.to_s)
          end
        end
        if expanded = node.expanded
          expanded.accept self
          return false
        end
        # `handler.call(x)`: the proc may have been made anywhere, kept in
        # program state and fetched here; each proc of its type may run.
        if node.name == "call" && (obj = node.obj) &&
           (type = obj.type?) && type.remove_typedef.is_a?(ProcInstanceType)
          wanted = type.remove_typedef
          @procs.call.each do |literal|
            next unless literal.type?.try(&.remove_typedef) == wanted
            saved = @via
            @via ||= literal.def
            walk_proc(literal)
            @via = saved
            break if @found
          end
        end
        node.target_defs.try &.each do |target|
          next if target.is_a?(External)
          location = target.location
          next if TapeRules.runtime?(@program, location) || TapeRules.std?(location)
          next if target.annotation(@program.tape_unsafe_annotation)
          next unless @seen.add?(target.object_id)
          saved = @via
          @via ||= target
          target.body.accept self
          @via = saved
        end
        true
      end

      def visit(node : Def | Macro)
        false
      end

      def visit(node : ASTNode)
        !@found
      end

      private def mutator?(name : String) : Bool
        MUTATORS.includes?(name) || name.ends_with?('!')
      end

      private def thread_local?(node : ClassVar) : Bool
        !!node.var?.try(&.thread_local?)
      end

      private def note(node : ASTNode, state : String) : Nil
        @found ||= {node, state, @via}
      end
    end

    # Every constant a body names, once each, with its value's type.
    class NamedConstants < Visitor
      getter paths = [] of {Path, Type}
      @seen = Set(Const).new

      def visit(node : Path) : Bool
        const = node.target_const
        type = node.type?
        @paths << {node, type} if const && type && @seen.add?(const)
        false
      end

      def visit(node : ASTNode) : Bool
        true
      end
    end

    # iyi: a class variable is module-level state as a constant is (iyi SPEC
    # III.4.5), named in the block's own text with nothing the closure
    # lists: a class method whose thread block and starter each ran
    # `@@count += 1` two million times compiled, and printed 2548908 and
    # 2461914 of 4000000. One only its initializer writes is a value, asked
    # what a constant is. One written again - by the block, or anywhere
    # the typer reached - is one cell every thread that names it shares,
    # refused as a captured local assigned after the start is. A
    # thread-local one is every thread's own, and neither.
    def check_thread_class_vars_share(a_def : Def, boundary : ShareBoundary) : Nil
      named = NamedClassVars.new
      a_def.body.accept named
      advice = "so every thread that reaches it shares one mutable cell: a data race (iyi SPEC III.4.5). Keep the value in an `Atomic`, or in one owner task that the others send RisBoard messages to"
      named.vars.each do |class_var, var|
        next if var.thread_local?
        next if var.type?.try { |type| TapeChecker.tape_in(@program, type) }
        if assign = named.assigns[var]?
          assign.raise "#{boundary.subject} assigns `#{class_var.name}`, a class variable, #{advice}"
        end
        if written = var.iyi_written
          write, in_def = written
          where = if in_def && in_def.name != "->"
                    "in `#{in_def.name}`"
                  elsif location = write.location
                    "at line #{location.line_number}"
                  else
                    "outside it"
                  end
          class_var.raise "#{boundary.subject} names the class variable `#{class_var.name}`, which is written after its initializer (#{where}), #{advice}"
        end
        type = var.type?
        next unless type
        if why = Iyi::Share.reason(type)
          class_var.raise "#{boundary.subject} names the class variable `#{class_var.name} : #{type}`, which is not Share: #{why} (iyi SPEC III.4.5)"
        end
      end
    end

    # Every class variable a body names, once each, with the variable it
    # is, and the first assignment to each.
    class NamedClassVars < Visitor
      getter vars = [] of {ClassVar, MetaTypeVar}
      getter assigns = {} of MetaTypeVar => ASTNode
      @seen = Set(MetaTypeVar).new

      def initialize
        @assigns.compare_by_identity
        @seen.compare_by_identity
      end

      def visit(node : Assign) : Bool
        target = node.target
        if target.is_a?(ClassVar) && (var = target.var?)
          @assigns[var] ||= node
        end
        true
      end

      def visit(node : ClassVar) : Bool
        var = node.var?
        @vars << {node, var} if var && @seen.add?(var)
        false
      end

      def visit(node : ASTNode) : Bool
        true
      end
    end

    # The assignments to one variable in a body, each with the loops,
    # blocks and procs around it and whether it comes after the call that
    # starts the thread. A name is the variable only where the innermost
    # scope's table says so: a block's own variable of the same name is
    # another cell.
    # ris: whether a call keeps its argument at *index* (SPEC 5.1): a
    # program method that stores it in a field, a class variable or a
    # collection, returns it, or hands it to a call that keeps it. std's
    # and the runtime's methods are not read: one given the value keeps
    # it unless it only prints or compares it.
    class KeptArgument
      PASSING = {"puts", "print", "p", "pp", "inspect", "to_s", "==", "!=",
                 "same?", "hash", "object_id", "raise"}

      @seen = Set(Tuple(UInt64, Int32)).new

      def initialize(@program : Program)
      end

      # The method through which it is kept, or nil.
      def keeps?(call : Call, index : Int32) : String?
        targets = call.target_defs
        return nil if PASSING.includes?(call.name) && call.obj.nil?
        return call.name unless targets
        targets.each do |target|
          next if target.is_a?(External) && !target.body
          if TapeRules.runtime?(@program, target.location) || TapeRules.std?(target.location)
            return target.name unless PASSING.includes?(target.name)
            next
          end
          next unless @seen.add?({target.object_id, index})
          arg = target.args[index]?
          return target.name unless arg && !target.splat_index
          walk = KeptParameter.new(self, arg.name)
          target.body.accept walk
          return walk.via || target.name if walk.kept || last_is?(target.body, walk.names)
        end
        nil
      end

      private def last_is?(body : ASTNode, names : Set(String)) : Bool
        last = body.is_a?(Expressions) ? body.expressions.last? : body
        last.is_a?(Var) && names.includes?(last.name)
      end
    end

    class KeptParameter < Visitor
      getter names : Set(String)
      getter kept = false
      getter via : String? = nil

      def initialize(@outer : KeptArgument, name : String)
        @names = Set{name}
      end

      def visit(node : Assign)
        value = node.value
        target = node.target
        if value.is_a?(Var) && @names.includes?(value.name)
          if target.is_a?(Var)
            @names << target.name
          else
            @kept = true
          end
        end
        true
      end

      def visit(node : Return)
        exp = node.exp
        @kept = true if exp.is_a?(Var) && @names.includes?(exp.name)
        true
      end

      def visit(node : ArrayLiteral | TupleLiteral | HashLiteral | NamedTupleLiteral)
        @kept = true if mentions?(node)
        true
      end

      def visit(node : Call)
        return false if @kept
        if expanded = node.expanded
          expanded.accept self
          return false
        end
        node.args.each_with_index do |arg, i|
          next unless arg.is_a?(Var) && @names.includes?(arg.name)
          if via = @outer.keeps?(node, i)
            @kept = true
            @via = via
          end
        end
        true
      end

      def visit(node : Def | Macro)
        false
      end

      def visit(node : ASTNode)
        !@kept
      end

      private def mentions?(node : ASTNode) : Bool
        found = false
        names = @names
        node.accept(MentionScan.new(names) { found = true })
        found
      end
    end

    class MentionScan < Visitor
      def initialize(@names : Set(String), &@hit : ->)
      end

      def visit(node : Var)
        @hit.call if @names.includes?(node.name)
        false
      end

      def visit(node : ASTNode)
        true
      end
    end

    class CaptureAssignments < Visitor
      getter assigns = [] of {ASTNode, Array(ASTNode), Bool}
      getter start_regions = [] of ASTNode
      getter uses = [] of Var
      getter aliases = [] of Assign
      getter? found_start = false

      def initialize(@program : Program, @meta : MetaVar, @start : Call?, vars : MetaVars?)
        @regions = [] of ASTNode
        @scopes = [vars] of MetaVars?
      end

      # ris: calls given the variable before the spawn, with its place
      # among their arguments: one that keeps it (`Holder.new(server)`)
      # leaves a second way to it.
      getter passed = [] of {Call, Int32}

      def visit(node : Call)
        if node.same?(@start)
          @found_start = true
          @start_regions = @regions.dup
          return false
        end
        if expanded = node.expanded
          expanded.accept self
          return false
        end
        unless @found_start
          node.args.each_with_index do |arg, i|
            if arg.is_a?(Var) && @scopes.last.try(&.[arg.name]?).same?(@meta)
              @passed << {node, i}
            end
          end
        end
        true
      end

      def visit(node : While)
        @regions << node
        true
      end

      def end_visit(node : While)
        @regions.pop
      end

      def visit(node : Block)
        @regions << node
        # iyi: a captured block is typed as the proc it becomes, so its
        # variables are that proc's table: the block's own held cells made
        # before it was captured, `v = 2` in a stored `keep { v = 2 }` read
        # as some other variable, and a thread reading the `v` it captured
        # while its starter called the block counted 28415 torn reads.
        fun_literal = node.fun_literal
        @scopes << (fun_literal.is_a?(ProcLiteral) ? fun_literal.def.vars : node.vars)
        true
      end

      def end_visit(node : Block)
        @scopes.pop
        @regions.pop
      end

      def visit(node : ProcLiteral)
        @regions << node
        @scopes << node.def.vars
        node.def.body.accept self
        @scopes.pop
        @regions.pop
        false
      end

      def visit(node : FileNode)
        @scopes << @program.file_module?(node.filename).try(&.vars)
        node.node.accept self
        @scopes.pop
        false
      end

      def visit(node : MultiAssign)
        if expanded = node.expanded
          expanded.accept self
          return false
        end
        true
      end

      # Macro code is its expansion. Walked as written it is the macro's text,
      # so `v = ...` inside `{% if true %}` after the start was never noted:
      # it compiled, and a thread reading the captured `Int64 | Float64`
      # counted 243585 torn reads in a debug build.
      def visit(node : MacroIf | MacroFor | MacroExpression | MacroVerbatim)
        node.expanded.try &.accept self
        false
      end

      def end_visit(node : MultiAssign)
        node.targets.each { |target| note(node, target) } unless node.expanded
      end

      def end_visit(node : Assign)
        note(node, node.target)
        # ris: a second name for the value (`other = server`) lets the
        # spawner reach it after the task took it.
        value = node.value
        target = node.target
        if !@found_start && value.is_a?(Var) && target.is_a?(Var) &&
           target.name != value.name &&
           (@scopes.last.try(&.[value.name]?).same?(@meta) ||
            @scopes.last.try(&.[target.name]?).same?(@meta))
          @aliases << node
        end
      end

      def end_visit(node : TypeDeclaration)
        note(node, node.var) if node.value
      end

      # A method's body is not this scope's code. A module's is: an iyi
      # file's top level is the body of the `module` its header names.
      def visit(node : Def | Macro | LibDef | AnnotationDef)
        false
      end

      # ris: a read of the variable once the task has started; a handed-off
      # value is never read by its spawner again.
      def visit(node : Var)
        if @found_start && @scopes.last.try(&.[node.name]?).same?(@meta)
          @uses << node
        end
        false
      end

      def visit(node : ASTNode)
        true
      end

      private def note(node : ASTNode, target : ASTNode) : Nil
        return unless target.is_a?(Var)
        return unless @scopes.last.try(&.[target.name]?).same?(@meta)
        @assigns << {node, @regions.dup, @found_start}
      end
    end

    class ClosuredVarsCollector < Visitor
      getter vars : Array(ASTNode)
      @a_def : Def

      def self.collect(a_def)
        visitor = new a_def
        a_def.accept visitor
        visitor.vars
      end

      def initialize(@a_def)
        @vars = [] of ASTNode
      end

      def visit(node : Var)
        if @a_def.vars.try &.[node.name]?.try &.closured?
          @vars << node
        end
        false
      end

      def visit(node : InstanceVar)
        @vars << node
        false
      end

      def visit(node : ASTNode)
        true
      end
    end

    # Whether a body, its inlined blocks and the procs inside it included,
    # calls a method on self without writing a receiver. A call is one when
    # its method takes a self argument, which is what codegen passes self
    # for: not a top-level def, a class method of a plain type, or a
    # function an import names (receiverless, but the module's).
    class ReceiverlessSelfCalls < Visitor
      getter? found = false

      def self.any?(body : ASTNode) : Bool
        visitor = new
        body.accept visitor
        visitor.found?
      end

      def visit(node : Call) : Bool
        return false if @found
        target_defs = node.target_defs
        if !node.obj && !node.uses_with_scope? && target_defs && target_defs.any?(&.owner.passed_as_self?)
          @found = true
          return false
        end
        true
      end

      def visit(node : ASTNode) : Bool
        !@found
      end
    end

    def check_args_are_not_closure(node, message)
      node.args.each do |arg|
        check_arg_is_not_closure(node, message, arg)
      end
    end

    def check_arg_is_not_closure(node, message, arg)
      case arg
      when Expressions
        arg.expressions.each do |exp|
          check_arg_is_not_closure(node, message, exp)
        end
      when Call
        # If the call simply returns its captured block unchanged, we can detect
        # closured vars inside the block during compile-time
        if target_def_is_captured_block?(arg)
          check_arg_is_not_closure(node, message, arg.block.not_nil!.fun_literal)
        end
      when ProcLiteral
        if proc_pointer = arg.proc_pointer
          case proc_pointer.obj
          when Var
            arg.raise "#{message} (closured vars: #{proc_pointer.obj})"
          when InstanceVar
            arg.raise "#{message} (closured vars: self)"
          end
        end

        if arg.def.closure?
          vars = ClosuredVarsCollector.collect arg.def
          if vars.empty?
            message += " (closured vars: self)"
          else
            message += " (closured vars: #{vars.join ", "})"
          end

          arg.raise message
        end
      when ProcPointer
        if expanded = arg.expanded
          return check_arg_is_not_closure(node, message, expanded)
        end

        if arg.obj.try &.type?.try &.passed_as_self?
          arg.raise "#{message} (closured vars: self)"
        end

        owner = arg.call.target_def.owner
        if owner.passed_as_self?
          arg.raise "#{message} (closured vars: self)"
        end
      end
    end

    # Checks whether *arg*'s target def has the following definition:
    #
    # ```
    # def f(&block)
    #   block
    # end
    # ```
    #
    # That is, the def returns its captured block and does nothing else. An
    # example is Proc.new(&block).
    def target_def_is_captured_block?(arg : Call)
      a_def = arg.target_defs.try &.first
      return false unless a_def

      block_arg = a_def.block_arg
      return false unless block_arg

      body_var = a_def.body.as?(Var)
      return false unless body_var && body_var.name == block_arg.name

      true
    end

    def transform(node : ProcPointer)
      super

      if expanded = node.expanded
        return transform(expanded)
      end

      if call = node.call?
        result = call.transform(self)

        # If the transform didn't end up in a Call, it means the
        # call will never be executed.
        if result.is_a?(Call)
          node.call = result
        end
      end

      node
    end

    def transform(node : ProcLiteral)
      check_tape_captures(node.def)
      body = node.def.body
      if node.def.no_returns? && !body.type?
        node.def.body = untyped_expression(body)
      else
        node.def.body = node.def.body.transform(self)
      end
      node
    end

    def untyped_expression(node, msg = nil)
      ex_msg = String.build do |str|
        str << "can't execute `" << node << "` at " << node.location
        if msg
          str << ": "
          str << msg
        end
      end

      build_raise ex_msg, node
    end

    def build_raise(msg : String, node : ASTNode)
      call = Call.global("raise", StringLiteral.new(msg).at(node)).at(node)
      call.accept MainVisitor.new(@program)
      call
    end

    def transform(node : Yield)
      if expanded = node.expanded
        return expanded.transform(self)
      end

      super

      # If the yield has a no-return expression, the yield never happens:
      # replace it with a series of expressions up to the one that no-returns.
      no_return_index = node.exps.index { |exp| !exp.type? || exp.no_returns? }
      if no_return_index
        exps = Expressions.new(node.exps[0, no_return_index + 1])
        exps.bind_to(exps.expressions.last)
        return exps
      end

      node
    end

    def transform(node : While)
      super

      # If the condition is a NoReturn, just replace the whole
      # while with it, since the body will never be executed
      if node.cond.no_returns?
        return node.cond
      end

      node
    end

    def transform(node : If)
      cond_is_truthy, cond_is_falsey = compute_last_truthiness do
        node.cond = node.cond.transform(self)
      end

      node_cond = node.cond

      if node_cond.no_returns?
        return node_cond
      end

      case
      when node_cond.true_literal?
        node.truthy = true
      when node_cond.false_literal?
        node.falsey = true
      when (cond_type = node_cond.type?) && cond_type.nil_type?
        node.falsey = true
      when cond_is_truthy
        node.truthy = true
      when cond_is_falsey
        node.falsey = true
      else
        # Not a special condition
      end

      if node.falsey?
        then_is_truthy = false
        then_is_falsey = false
      else
        then_is_truthy, then_is_falsey = compute_last_truthiness do
          node.then = node.then.transform(self)
        end
      end

      if node.truthy?
        else_is_truthy = false
        else_is_falsey = false
      else
        else_is_truthy, else_is_falsey = compute_last_truthiness do
          node.else = node.else.transform(self)
        end
      end

      case node
      when .and?
        @last_is_truthy = cond_is_truthy && then_is_truthy
        @last_is_falsey = cond_is_falsey || then_is_falsey
      when .or?
        @last_is_truthy = cond_is_truthy || else_is_truthy
        @last_is_falsey = cond_is_falsey && else_is_falsey
      else
        reset_last_status
      end

      node
    end

    def transform(node : IsA)
      super
      reset_last_status
      if replacement = node.syntax_replacement
        return replacement.transform(self)
      end

      const_type = node.const.type?
      return untyped_expression(node) unless const_type

      transform_is_a_or_responds_to node, &.filter_by(const_type)
    end

    def transform(node : RespondsTo)
      super
      reset_last_status
      transform_is_a_or_responds_to node, &.filter_by_responds_to(node.name)
    end

    def transform_is_a_or_responds_to(node, &)
      obj = node.obj

      if obj_type = obj.type?
        filtered_type = yield obj_type

        if obj_type == filtered_type
          @last_is_truthy = true
          if var?(obj)
            return true_literal
          else
            exps = Expressions.new([obj, true_literal] of ASTNode)
            exps.type = @program.bool
            return exps
          end
        end

        unless filtered_type
          @last_is_falsey = true
          if var?(obj)
            return false_literal
          else
            exps = Expressions.new([obj, false_literal] of ASTNode)
            exps.type = @program.bool
            return exps
          end
        end
      end

      node
    end

    def var?(node)
      case node
      when Var, InstanceVar, ClassVar, Global
        true
      else
        false
      end
    end

    def transform(node : Cast)
      node = super

      obj_type = node.obj.type?
      return node unless obj_type

      if node.obj.no_returns?
        return node.obj
      end

      to_type = node.to.type

      if to_type.pointer?
        if obj_type.pointer? || obj_type.reference_like?
          return node
        else
          node.raise "can't cast #{obj_type} to #{to_type}"
        end
      end

      if obj_type.pointer?
        unless to_type.pointer? || to_type.reference_like?
          node.raise "can't cast #{obj_type} to #{to_type}"
        end
      else
        resulting_type = obj_type.filter_by(to_type)
        unless resulting_type
          node.raise "can't cast #{obj_type} to #{to_type}"
        end
      end

      node
    end

    def transform(node : NilableCast)
      node = super

      if node.obj.no_returns?
        return node.obj
      end

      node
    end

    def transform(node : FunDef)
      node_body = node.body
      return node unless node_body

      node.body = node_body.transform(self)

      if node_external = node.external
        node_external.body = node_external.body.transform(self)
      end
      node
    end

    def transform(node : ExceptionHandler)
      node = super

      if node.body.no_returns?
        node.else = nil
      end

      node
    end

    def transform(node : InstanceSizeOf)
      exp_type = node.exp.type?

      if exp_type
        instance_type = exp_type.devirtualize
        if instance_type.struct? || instance_type.module? || instance_type.metaclass? || instance_type.is_a?(UnionType)
          node.exp.raise "instance_sizeof can only be used with a class, but #{instance_type} is a #{instance_type.type_desc}"
        end
      end

      if expanded = node.expanded
        return expanded.transform self
      end

      node
    end

    def transform(node : InstanceAlignOf)
      exp_type = node.exp.type?

      if exp_type
        instance_type = exp_type.devirtualize
        if instance_type.struct? || instance_type.module? || instance_type.metaclass? || instance_type.is_a?(UnionType)
          node.exp.raise "instance_alignof can only be used with a class, but #{instance_type} is a #{instance_type.type_desc}"
        end
      end

      if expanded = node.expanded
        return expanded.transform self
      end

      node
    end

    def transform(node : TupleLiteral)
      super

      unless node.elements.all? &.type?
        return untyped_expression node
      end

      no_return_index = node.elements.index &.no_returns?
      if no_return_index
        exps = Expressions.new(node.elements[0, no_return_index + 1])
        exps.bind_to(exps.expressions.last)
        return exps
      end

      # `node.program` is assigned by `MainVisitor` usually, however
      # it may not be assigned in some edge-case (e.g. this `node` is placed
      # at not invoked block.). This assignment is for it.
      node.program = @program
      node.update
      node.validate_splats!

      node
    end

    def transform(node : NamedTupleLiteral)
      super

      unless node.entries.all? &.value.type?
        return untyped_expression node
      end

      no_return_index = node.entries.index &.value.no_returns?
      if no_return_index
        exps = Expressions.new(node.entries[0, no_return_index + 1].map &.value)
        exps.bind_to(exps.expressions.last)
        return exps
      end

      node.program = @program
      node.update

      node
    end

    def transform(node : CStructOrUnionDef)
      type = node.resolved_type.as(NonGenericClassType)
      node.raise "empty #{type.type_desc}s are disallowed" if type.instance_vars.empty?
      node
    end

    def transform(node : Primitive)
      extra = node.extra
      extra = extra.transform(self) if extra

      # For `allocate` on a virtual abstract type we make `extra`
      # be a call to `raise` at runtime. Here we just replace the
      # "allocate" primitive with that raise call.
      if node.name.in?("allocate", "program_allocate", "pre_initialize") && extra
        return extra
      end

      node.extra = extra
      node
    end

    def transform(node : TypeOf)
      node = super

      unless node.type?
        node.unbind_from node.dependencies
        node.bind_to node.expressions
      end

      node
    end

    def transform(node : AssignWithRestriction)
      transform(node.assign)
    end

    @false_literal : BoolLiteral?

    def false_literal
      @false_literal ||= begin
        false_literal = BoolLiteral.new(false)
        false_literal.set_type(@program.bool)
        false_literal
      end
    end

    @true_literal : BoolLiteral?

    def true_literal
      @true_literal ||= begin
        true_literal = BoolLiteral.new(true)
        true_literal.set_type(@program.bool)
        true_literal
      end
    end

    def simple_constant?(node)
      simple_constant?(node, [] of Const)
    end

    def simple_constant?(node, consts)
      case node
      when NilLiteral, BoolLiteral, CharLiteral, NumberLiteral, StringLiteral
        return true
      when Call
        obj = node.obj
        return false unless obj

        case node.args.size
        when 0
          case node.name
          when "+", "-", "~"
            return simple_constant?(obj, consts)
          end
        when 1
          case node.name
          when "+", "-", "*", "&+", "&-", "&*", "/", "//", "&", "|"
            return simple_constant?(obj, consts) && simple_constant?(node.args.first, consts)
          end
        end
      when Path
        if target_const = node.target_const
          return false if consts.includes?(target_const)

          consts << target_const
          return simple_constant?(target_const.value, consts)
        end
      end

      false
    end
  end
end
