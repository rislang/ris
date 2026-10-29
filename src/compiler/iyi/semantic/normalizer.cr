require "../program"
require "../syntax/transformer"

module Iyi
  class Program
    getter ris_growing_field_names = Set(String).new
    getter ris_text_companions = {} of Type => Set(String)

    def normalize(node, inside_exp = false, current_def = nil, macro_code = false)
      if node.is_a?(Call) || node.is_a?(Assign)
        if !current_def && !macro_code &&
           node.location.try(&.original_filename).try(&.ends_with?(".ri"))
          return normalize(Expressions.new([node] of ASTNode).at(node),
            inside_exp, current_def, macro_code)
        end
      end
      normalizer = Normalizer.new(self)
      normalizer.macro_code = 1 if macro_code
      normalizer.current_def = current_def
      normalizer.macro_expansion = node if Normalizer.macro_expansion?(node)
      # ris: the program's top level is a scope of its own (a def's body
      # is lowered with the def).
      unless current_def || macro_code || normalizer.macro_expansion || node.is_a?(Def)
        normalizer.prepare_collection_inference(node)
        TapeTextLowering.lower_scope(node, [] of String, false)
        if node.is_a?(Expressions)
          prepared = normalizer.prepare_text_growth(Expressions.new(node.expressions).at(node))
          if prepared.is_a?(Expressions) && !prepared.same?(node)
            node.expressions = prepared.expressions
          end
        end
        normalizer.bound_scope = node
      end
      node.transform(normalizer)
    end
  end

  class Normalizer < Transformer
    getter program : Program

    # The current method where we are normalizing.
    # This is used to expand argless `super` and `previous_def`
    # to their version with arguments copied from the current method.
    property current_def : Def?

    # iyi: the top of a macro's expansion, when that is what is being
    # normalized. Its statements are the enclosing scope's, not a scope of
    # their own, so a `defer` among them is left standing for the main
    # visitor to lower over the rest of that scope
    # (`MainVisitor#iyi_splice_macro_defers`). Lowered here, it covered
    # nothing: `{% if true %} defer puts "a" {% end %}` printed "a" before
    # the body after it.
    property macro_expansion : ASTNode?

    @dead_code = false

    # ris: where a local's one assignment is looked for, so that
    # TapeCheckFreeLowering may take `n = a.bytesize` for the size: the
    # def being normalized, or the whole top level; nil in a macro's
    # expansion, which does not see the rest of its def.
    property bound_scope : ASTNode?
    @bound_params = [] of String

    # ris: the fields the class being normalized declares
    # `Str::Scanner`, whose loops TapeCursorLowering runs on locals.
    @scanners = [] of String

    # A macro's expansion is parsed from a `VirtualFile`, and it is the
    # only source that is.
    def self.macro_expansion?(node : ASTNode) : Bool
      location = node.location
      location ||= node.expressions.first?.try(&.location) if node.is_a?(Expressions)
      location.try(&.filename).is_a?(VirtualFile)
    end

    def initialize(@program)
    end

    def before_transform(node)
      @dead_code = false
    end

    def after_transform(node)
      case node
      when Return, Break, Next
        @dead_code = true
      when If, Unless, Expressions, Block, Assign
        # Skip
      else
        @dead_code = false
      end
    end

    def transform(node : Expressions)
      exps = [] of ASTNode
      node.expressions.each do |exp|
        # iyi: a `defer` is left standing here on purpose. What it defers past
        # is everything after it in *this* list, which is only known once the
        # list is complete — see `apply_defers` below.
        if exp.is_a?(Defer)
          exp.exp = exp.exp.transform(self)
          exps << exp
          next
        end

        new_exp = exp.transform(self)
        if new_exp
          if new_exp.is_a?(Expressions)
            exps.concat new_exp.expressions
          else
            exps << new_exp
          end
        end
        break if @dead_code
      end
      exps = apply_defers(exps) unless node.same?(@macro_expansion)
      # Parentheses do not hide a static literal from heap-place autocast.
      if exps.size == 1 && (text = exps.first).is_a?(Call) &&
         text.tape_literal?
        return text
      end
      case exps.size
      when 0
        Nop.new
      else
        node.expressions = exps
        node
      end
    end

    # iyi: `defer` — cleanup that runs however the scope is left
    # (SPEC.md III.1.4).
    #
    # From:
    #
    #     a
    #     defer x
    #     b
    #     defer y
    #     c
    #
    # To:
    #
    #     a
    #     %live = true
    #     __iyi_defer_push(-> { x if %live; nil })
    #     begin
    #       b
    #       __iyi_defer_push(-> { y if %live; nil })
    #       begin
    #         c
    #       ensure
    #         %live = false
    #         __iyi_defer_pop_run
    #         %live = true
    #         y
    #       end
    #     ensure
    #       %live = false
    #       __iyi_defer_pop_run
    #       x
    #     end
    #
    # Every ordinary exit — falling off the end, a `return`, `!` expanding
    # to a `return` (III.1.2) — reaches the `ensure`, which runs the
    # cleanup there, inline, as the scope's own code. A panic reaches none
    # of them: `raise` never unwinds (there is no unwinder to link, by
    # design), so the cleanup is also registered, as a proc the runtime
    # holds, and the panic path walks the registry and runs what was never
    # popped. The ordinary exit disarms its proc before popping it, so the
    # registry stays balanced and the cleanup runs once.
    #
    # One `%live` serves every `defer` of the list: the pop runs only the
    # proc on top, which is the one being disarmed, and the flag is armed
    # again after it for the procs of the same list still registered. A
    # flag for each `defer` was a variable for each, and every handler
    # nested inside copies every variable in scope: N `defer`s in one
    # scope were N^2 copies.
    #
    # The proc used to be the only copy, run by the pop too, and a proc is
    # a closure: in a struct method it read a copy of `self` made at entry
    # (`defer puts @n` printed 0 after `@n = 2`) and wrote into that copy,
    # and every variable it named stopped narrowing. Inline, the cleanup is
    # typed and run as an `ensure` is; the proc runs only when the frame
    # never resumes, which is what lets the semantic pass keep a captured
    # variable's narrowing (`Def#iyi_defer?`).
    #
    # **LIFO falls out of the nesting** twice over: a second `defer`
    # expands inside the first one's body, so its push is later and its
    # pop earlier — and the registry is a stack, so the panic path
    # agrees.
    #
    # **The scope is the block, not the function.** This is a deliberate
    # departure from Go, and it is the shape of the lowering rather than an
    # extra rule: a `defer` in a loop body runs at the end of each iteration
    # instead of piling up until the function returns, which is Go's
    # best-known wart with the feature.
    def apply_defers(exps : Array(ASTNode), live : Var? = nil) : Array(ASTNode)
      index = exps.index { |exp| exp.is_a?(Defer) }
      return exps unless index

      deferred = exps[index].as(Defer)
      head = exps[0...index]

      # ris: the trusted tape guard needs no captured `live` flag or fresh
      # registry node. One cached node per fiber preserves the ordinary
      # defer order on panic; normal exits detach it and release inline.
      if tape_cleanup?(deferred)
        rest = apply_defers(exps[(index + 1)..], live)
        head << Call.new(nil, "__iyi_tape_defer_push", global: true).at(deferred)
        pop = Call.new(nil, "__iyi_tape_defer_pop", global: true).at(deferred)
        cleanup = Expressions.new([pop, deferred.exp] of ASTNode).at(deferred)
        head << ExceptionHandler.new(rest, ensure: cleanup).at(deferred).tap(&.iyi_defer=(true))
        return head
      end

      if program.iyi_prelude?
        # An earlier `defer` of this list made the flag, and its proc is
        # still registered when this one is popped.
        outer = live
        live ||= Var.new(program.new_temp_var_name).at(deferred)
        rest = apply_defers(exps[(index + 1)..], live)
        # The trailing `nil` pins the proc to `-> Nil`: a proc literal
        # does not coerce its return the way a block restriction does,
        # and a cleanup's value is nobody's.
        armed = If.new(live.clone, deferred.exp.clone).at(deferred)
        cleanup_body = Expressions.new([armed, NilLiteral.new.at(deferred)] of ASTNode).at(deferred)
        cleanup = Def.new("->", [] of Arg, cleanup_body).at(deferred)
        cleanup.iyi_defer = true
        push = Call.global("__iyi_defer_push", ProcLiteral.new(cleanup).at(deferred)).at(deferred)
        pop = Call.new(nil, "__iyi_defer_pop_run", global: true).at(deferred)
        disarm = Assign.new(live.clone, BoolLiteral.new(false).at(deferred)).at(deferred)
        ordinary_exit = [disarm, pop] of ASTNode
        ordinary_exit << Assign.new(live.clone, BoolLiteral.new(true).at(deferred)).at(deferred) if outer
        ordinary_exit << deferred.exp
        head << Assign.new(live.clone, BoolLiteral.new(true).at(deferred)).at(deferred) unless outer
        head << push
        head << ExceptionHandler.new(rest, ensure: Expressions.new(ordinary_exit).at(deferred)).at(deferred).tap(&.iyi_defer=(true))
      else
        # Crystal's prelude has a real unwinder, so the classic shape —
        # the cleanup inline in the `ensure` — already runs on a panic.
        rest = apply_defers(exps[(index + 1)..])
        head << ExceptionHandler.new(rest, ensure: deferred.exp).at(deferred).tap(&.iyi_defer=(true))
      end
      head
    end

    private def tape_cleanup?(deferred : Defer) : Bool
      return false unless program.iyi_prelude? && @current_def.try(&.name) == "tape_scope"
      call = deferred.exp
      return false unless call.is_a?(Call) && call.global? && call.name == "__iyi_tape_release"
      return false unless call.args.empty? && call.named_args.nil? && call.block.nil? && call.obj.nil?
      directory = program.iyi_prelude_dir
      # The shared tape now lives beside the allocator choices.
      file = deferred.location.try(&.original_filename)
      !!(directory && {"prelude.iyi", "region.iyi"}.any? do |name|
        file == File.join(directory, name)
      end)
    end

    # A `defer` that is not one of several expressions — the whole of a body,
    # say — has nothing after it to defer past, so all that is left of it is
    # the cleanup itself, still guarded so that it runs on an unwind.
    def transform(node : Defer)
      if node.same?(@macro_expansion)
        # A macro's whole expansion: left standing, as in a list of them.
        node.exp = node.exp.transform(self)
        return Expressions.new([node] of ASTNode).at(node)
      end
      ExceptionHandler.new(Nop.new, ensure: node.exp.transform(self)).at(node).tap(&.iyi_defer=(true))
    end

    # iyi: the typed group — SPEC.md III.4.9.
    #
    # From:
    #
    #     group do |g|
    #       x = g.spawn { read(a) }
    #       y = g.spawn { read(b) }
    #     end!
    #
    # To (inside the `!`'s own expansion):
    #
    #     group do |g|
    #       %h1 = g.spawn { read(a) }
    #       x = %h1
    #       %h2 = g.spawn { read(b) }
    #       y = %h2
    #       %v1 = %h1.value
    #       %v2 = %h2.value
    #       %first = g.first_failure
    #       if %v1.is_a?(::Error) && %h1.fiber.object_id == %first
    #         %v1
    #       elsif %v2.is_a?(::Error) && %h2.fiber.object_id == %first
    #         %v2
    #       elsif %v1.is_a?(::Error)
    #         %v1
    #       elsif %v2.is_a?(::Error)
    #         %v2
    #       else
    #         {%v1, %v2}
    #       end
    #     end
    #
    # The block stays a block, which is the hygiene: a name a task's body
    # uses stays scoped to it, instead of being inlined into the caller
    # where a later closure over the same name would freeze its type. The
    # group method answers what its block answers, so the appended
    # extraction *is* the group's value, and `!` applies through III.1.2's
    # ordinary machinery: the tuple's elements are non-error by the same
    # `is_a?(::Error)` narrowing `!` expands to, and the error side is the
    # union of what the branches answer. The method's deferred join stays
    # — a `return` between two spawns still joins.
    #
    # Under `end!` the values are read before any join: a read waits for
    # its task, and reading a panicked task's value is what catches the
    # panic as `Panicked` (III.1.4), so the deferred join finds nothing
    # owed. With a `g.join` first, the join re-raised the panic nobody had
    # read yet and the program died where the group was to answer
    # `Panicked`. A group without `!` joins first, as before: nothing
    # reads its answer for it, and a panic it swallowed into a discarded
    # tuple would be a bug nobody heard of.
    #
    # The error that leaves is the one that stopped the group: the first
    # failure cancels its siblings, and a sibling cancelled earlier in the
    # text answers `Cancelled`, which the slots in text order answered in
    # its place. The runtime keeps the failing task's object_id
    # (`IyiGroup#first_failure`), and its slot is asked first.
    #
    # Each slot reads a handle of its own (`%h1`, `%h2`), never the author's
    # variable: one name reused for two spawns (`t = g.spawn {..}` twice)
    # read the last task twice, answering {2, 2} for {1, 2} and losing the
    # first task's error.
    #
    # What qualifies is what the section says: the block's parameter is used
    # as the receiver of direct `spawn` statements and *nowhere else*, and
    # the block ends in one. A spawn in a loop, an `if`, a `g` that escapes,
    # or macro code anywhere in the block (whose expansion may spawn) falls
    # back quietly to the general form, whose group is its block's last
    # expression and whose handles answer through `task.value`; a `!`
    # demanding the typed form of a group that cannot have one is refused
    # by `!`'s own degenerate-union check, which names the type it found.
    # A block whose last expression is its own — `"sum is #{a.value}"`
    # after two spawns — answers that: the expansion threw it away and
    # answered the tuple.
    private def expand_iyi_group(node : Call, propagated : Bool) : ASTNode?
      block = node.block
      return nil unless block
      group_param = block.args.first?
      return nil unless group_param

      body = block.body
      statements = body.is_a?(Expressions) ? body.expressions.dup : [body] of ASTNode
      last = statements.last?
      return nil unless last && iyi_direct_spawn(last, group_param.name)

      handles = [] of ASTNode
      # Which handles are tuple slots. `_ = g.spawn {..}` is III.4.9's
      # explicit discard, and it took a slot all the same: `{30, 40}` for
      # `{40}`. Its value is still read below, so a failure that stopped
      # the group still leaves it and a panic still arrives as `Panicked`.
      slots = [] of Bool
      rewritten = [] of ASTNode

      statements.each do |statement|
        spawn_call = iyi_direct_spawn(statement, group_param.name)
        if spawn_call.is_a?(Call)
          # `%h1 = g.spawn {..}`, and the author's `x = %h1` after it.
          handle = Var.new(program.new_temp_var_name).at(statement)
          handles << handle
          discarded = statement.is_a?(Assign) && statement.target.is_a?(Underscore)
          slots << !discarded
          rewritten << Assign.new(handle.clone, spawn_call).at(statement)
          if statement.is_a?(Assign) && !discarded
            rewritten << Assign.new(statement.target, handle.clone).at(statement)
          end
        else
          # Any other use of the group parameter anywhere in the statement
          # disqualifies: the tuple's arity has to be a fact of the text.
          return nil if iyi_uses_var?(statement, group_param.name)
          rewritten << statement
        end
      end

      group_var = Var.new(group_param.name).at(node)
      rewritten << Call.new(group_var.clone, "join").at(node) unless propagated

      values = [] of ASTNode
      tuple = [] of ASTNode
      handles.each_with_index do |handle, index|
        value = Var.new(program.new_temp_var_name).at(node)
        values << value
        tuple << value.clone if slots[index]
        rewritten << Assign.new(value.clone, Call.new(handle.clone, "value").at(node)).at(node)
      end

      extraction = TupleLiteral.new(tuple).at(node).as(ASTNode)
      values.reverse_each do |value|
        is_error = IsA.new(value.clone, Path.global("Error").at(node)).at(node)
        extraction = If.new(is_error, value.clone, extraction).at(node)
      end

      if handles.size > 1
        first = Var.new(program.new_temp_var_name).at(node)
        rewritten << Assign.new(first.clone, Call.new(group_var.clone, "first_failure").at(node)).at(node)
        handles.zip(values).reverse_each do |handle, value|
          is_error = IsA.new(value.clone, Path.global("Error").at(node)).at(node)
          fiber_id = Call.new(Call.new(handle.clone, "fiber").at(node), "object_id").at(node)
          stopped_the_group = Call.new(fiber_id, "==", first.clone).at(node)
          extraction = If.new(And.new(is_error, stopped_the_group).at(node), value.clone, extraction).at(node)
        end
      end
      rewritten << extraction

      block.body = Expressions.new(rewritten).at(node)
      # The same call node, rewritten; the flag comes off so the transform
      # this returns into normalizes the new body instead of reasking.
      node.iyi_group = false
      node
    end

    # The statement's own spawn, when the statement is exactly a direct one:
    # `g.spawn { }` bare, or assigned to a variable or an underscore. A
    # parallel task (`g.spawn_parallel { }`, SPEC.md III.4.13) is a task of
    # the group like any other, and takes its slot the same way.
    private def iyi_direct_spawn(statement : ASTNode, group_name : String) : Call?
      target = statement.is_a?(Assign) ? statement.value : statement
      return nil unless target.is_a?(Call)
      return nil unless (target.name == "spawn" || target.name == "spawn_parallel") && target.block
      receiver = target.obj
      return nil unless receiver.is_a?(Var) && receiver.name == group_name
      # The spawn's own block must not smuggle the group out either.
      spawn_block = target.block
      return nil if spawn_block && iyi_uses_var?(spawn_block, group_name)
      target
    end

    # Whether *node* uses the variable *name*, or holds macro code: what a
    # `{% for %}` writes is text until the main visitor expands it, so
    # `y{{i}} = g.spawn {..}` in one was invisible here, and the tuple came
    # out one slot short with those tasks' errors dropped.
    private def iyi_uses_var?(node : ASTNode, name : String) : Bool
      scan = IyiVarScan.new(name)
      node.accept(scan)
      scan.found?
    end

    # :nodoc:
    class IyiVarScan < Visitor
      getter? found = false

      def initialize(@name : String)
      end

      def visit(node : Var)
        @found = true if node.name == @name
        true
      end

      # iyi: a block whose parameter has the name is a scope of its own:
      # a task's `group do |g|` uses its `g`, not the group's, and taking
      # it for the group's made the outer group answer its last handle -
      # `IyiTask(Int32)` for `{1, 2}`, and `end!` refused.
      def visit(node : Block)
        node.args.none? { |arg| arg.name == @name }
      end

      def visit(node : MacroIf | MacroFor | MacroExpression | MacroVerbatim | MacroLiteral)
        @found = true
        false
      end

      def visit(node : ASTNode)
        true
      end
    end

    # Code a program wrote, not std, the runtime or an artifact.
    private def ris_program_code?(node : ASTNode) : Bool
      return false unless program.iyi_prelude?
      location = node.location
      return false unless location
      return false if TapeScopeRuntime.runtime?(location)
      file = location.original_filename.try(&.gsub('\\', '/')) || ""
      !(file.includes?("/src/std/") || file.ends_with?(".iyimod"))
    end

    @ris_growing_locals = Set(String).new
    @ris_text_slots = {} of String => Var
    @ris_growing_fields = Set(String).new
    @ris_text_reassigned = Set(String).new

    # Scan before normalization introduces temporaries and rebinding calls.
    class GrowingTextScan < Visitor
      getter locals = Set(String).new
      getter fields = Set(String).new
      getter assigned = Set(String).new
      getter assignments = Hash(String, Int32).new(0)
      getter block_args = Set(String).new
      # Locals started from text, and locals passed as call arguments:
      # both together may meet a String::Builder parameter.
      getter text_starts = Set(String).new
      getter arguments = Set(String).new

      def visit(node : Assign)
        if (field = node.target).is_a?(InstanceVar) &&
           (node.value.is_a?(ArrayLiteral) || node.value.is_a?(HashLiteral))
          @non_text_fields << field.name
        end
        if (target = node.target).is_a?(Var)
          @assigned << target.name
          @assignments[target.name] += 1
          if node.value.is_a?(StringLiteral) ||
             node.value.is_a?(StringInterpolation)
            @text_starts << target.name
          end
        end
        true
      end

      def visit(node : TypeDeclaration)
        if node.value && (target = node.var).is_a?(Var)
          @assigned << target.name
          @assignments[target.name] += 1
        end
        if (field = node.var).is_a?(InstanceVar) &&
           GrowingTextScan.never_string?(node.declared_type)
          @non_text_fields << field.name
        end
        true
      end

      # Fields declared as, or started from, a type that cannot be a String
      # (`@x : Array(T)`, `@x = [] of T`) need no text companion.
      getter non_text_fields = Set(String).new

      def self.never_string?(type : ASTNode) : Bool
        case type
        when Generic
          true
        when Path
          type.names != ["String"]
        when Union
          type.types.all? { |part| never_string?(part) }
        else
          false
        end
      end

      def visit(node : MultiAssign)
        node.targets.each do |target|
          target = target.exp if target.is_a?(Splat)
          if target.is_a?(Var)
            @assigned << target.name
            @assignments[target.name] += 1
          end
        end
        true
      end

      def visit(node : Block)
        node.args.each { |arg| @block_args << arg.name }
        true
      end

      def initialize(@methods = false)
      end

      def visit(node : Call)
        if node.name == "<<" && node.args.size == 1
          case receiver = node.obj
          when Var
            @locals << receiver.name
          when InstanceVar
            @fields << receiver.name
          end
        elsif Normalizer.lending_call?(node)
          node.args.each { |arg| @arguments << arg.name if arg.is_a?(Var) }
        end
        true
      end

      def visit(node : Def)
        @methods
      end

      def visit(node : ClassDef | ModuleDef | Macro)
        false
      end

      def visit(node : ASTNode)
        true
      end
    end

    # How a program uses one String::Builder local or String.build block
    # argument. When every use is `<<`, `finish` or `to_s`, `text = ""` does
    # the same and the builder is refused (TODO "Text"). A builder passed to
    # a call stays: an overload on String (`join(separator)`) would take the
    # text silently, and an untyped parameter would get a String.
    class BuilderUses < Visitor
      SIMPLE = {"<<", "finish", "to_s"}
      getter total = 0
      getter accounted = 0
      getter assigns = 0
      getter appends = 0

      def initialize(@name : String)
      end

      # An unused builder may hold room on purpose: only appended ones.
      def simple? : Bool
        @appends > 0 && @total == @accounted && @assigns <= 1
      end

      def visit(node : Var)
        @total += 1 if node.name == @name
        true
      end

      def visit(node : Assign)
        if (target = node.target).is_a?(Var) && target.name == @name
          @accounted += 1
          @assigns += 1
        end
        true
      end

      def visit(node : Call)
        if (obj = node.obj).is_a?(Var) && obj.name == @name &&
           SIMPLE.includes?(node.name)
          @accounted += 1
          @appends += 1 if node.name == "<<"
        end
        true
      end

      def visit(node : Def | ClassDef | ModuleDef | Macro)
        false
      end

      def visit(node : ASTNode)
        true
      end
    end

    class BuilderStarts < Visitor
      getter locals = [] of {String, Call}
      getter blocks = [] of {String, Call}

      def visit(node : Assign)
        if (target = node.target).is_a?(Var) && (value = node.value).is_a?(Call) &&
           value.name == "new" && (obj = value.obj).is_a?(Path) &&
           obj.names == ["String", "Builder"] && !value.block
          @locals << {target.name, value}
        end
        true
      end

      def visit(node : Call)
        if node.name == "build" && (obj = node.obj).is_a?(Path) &&
           obj.names == ["String"] && (block = node.block) &&
           block.args.size == 1
          @blocks << {block.args.first.name, node}
        end
        true
      end

      def visit(node : Def | ClassDef | ModuleDef | Macro)
        false
      end

      def visit(node : ASTNode)
        true
      end
    end

    private def refuse_plain_builders(body : ASTNode) : Nil
      return unless ris_program_code?(body)
      starts = BuilderStarts.new
      body.accept(starts)
      starts.locals.each do |name, call|
        uses = BuilderUses.new(name)
        body.accept(uses)
        next unless uses.simple?
        # The edit replaces the whole `String::Builder.new(...)`, which
        # starts at its path; the call's own location is the method name.
        start = call.obj.not_nil!
        size = nil
        if (from = start.location) && (to = call.end_location) &&
           from.line_number == to.line_number
          size = to.column_number - from.column_number + 1
        end
        start.raise "`#{name}` only appends and is read back: write " \
                   "`#{name} = \"\"`, append with `<<` and read `#{name}` " \
                   "itself (not `#{name}.finish`). A String local grows in " \
                   "place and is lent to String::Builder parameters.",
          suggestion: "\"\"", size: size
      end
      starts.blocks.each do |name, call|
        uses = BuilderUses.new(name)
        call.block.not_nil!.body.accept(uses)
        next unless uses.simple?
        call.raise "this String.build only appends: write `#{name} = \"\"`, " \
                   "append with `<<`, then use `#{name}`. A String local " \
                   "grows in place and is lent to String::Builder parameters."
      end
    end

    private def growing_slot(receiver : ASTNode) : ASTNode
      case receiver
      when Var
        @ris_text_slots[receiver.name].clone.at(receiver)
      when InstanceVar
        InstanceVar.new("@__ris_text_#{receiver.name.lchop('@')}").at(receiver)
      else
        raise "BUG: growing text needs a binding"
      end
    end

    private def growing_initializer(receiver : ASTNode) : ASTNode
      If.new(IsA.new(receiver.clone, Path.global("String")).at(receiver),
        Call.new(Path.global("RisTextGrowth"), "new").at(receiver),
        NilLiteral.new.at(receiver)).at(receiver)
    end

    def prepare_text_growth(body : ASTNode, params = [] of String) : ASTNode
      @ris_growing_locals = Set(String).new
      @ris_text_slots = {} of String => Var
      return body unless program.tape_platform? && @macro_code == 0 &&
                         !TapeScopeRuntime.runtime?(body.location)
      refuse_plain_builders(body)
      scan = GrowingTextScan.new
      body.accept(scan)
      @ris_growing_locals = scan.locals
      # Lend only a local assigned once: a rebinding (`kept = x.copy_to(...)`
      # in a tape block) must keep its own lowering and lifetime checks.
      if ris_program_code?(body)
        once = scan.assignments.select { |_, n| n == 1 }.keys.to_set
        @ris_growing_locals |= (scan.text_starts & scan.arguments & once) -
                               scan.block_args
      end
      @ris_text_reassigned = scan.assignments.select { |_, n| n > 1 }.keys.to_set
      @ris_growing_locals.each do |name|
        slot = program.new_temp_var.at(body)
        slot.ris_text_slot = true
        @ris_text_slots[name] = slot
      end
      names = @ris_growing_locals.select do |name|
        params.includes?(name) ||
          (!scan.assigned.includes?(name) && !scan.block_args.includes?(name))
      end
      lines = @ris_growing_locals.select { |name| names.includes?(name) || @ris_text_reassigned.includes?(name) }.map do |name|
        slot = growing_slot(Var.new(name).at(body))
        initial = names.includes?(name) ?
          growing_initializer(Var.new(name).at(body)) : NilLiteral.new.at(body)
        Assign.new(slot, initial).at(body).as(ASTNode)
      end
      return body if lines.empty?
      Expressions.new(lines + [body]).at(body)
    end

    @ris_growing_rebounds = Set(UInt64).new
    @ris_string_mutations = Set(UInt64).new
    @ris_text_arg_calls = Set(UInt64).new

    # `s << "a" << "b"`: a String's << rebinds `s` and answers its new text,
    # so the next link appends to `s` again. Any other receiver keeps the
    # returned value (Int's shift chains, IO and Array answer self).
    private def text_append_chain(node : Call) : ASTNode?
      return nil unless program.tape_platform? && @macro_code == 0 &&
                        ris_program_code?(node) &&
                        node.name == "<<" && node.args.size == 1 &&
                        !node.block && !node.block_arg &&
                        (inner = node.obj).is_a?(Call)
      root = inner
      while root.is_a?(Call) && root.name == "<<" && root.args.size == 1 &&
            !root.block && !root.block_arg
        root = root.obj
      end
      return nil unless root.is_a?(Var) || root.is_a?(InstanceVar)
      value = program.new_temp_var.at(node)
      again = Call.new(root.clone, "<<", node.args.map(&.clone)).at(node)
      other = Call.new(value.clone, "<<", node.args.map(&.clone)).at(node)
      @ris_string_mutations << other.object_id
      Expressions.new([
        Assign.new(value, inner).at(node),
        If.new(IsA.new(value.clone, Path.global("String").at(node)).at(node),
          again, other).at(node),
      ] of ASTNode).at(node)
    end

    # A named call that may take a growing local as a String::Builder.
    # Operators and the lowering's own calls never do.
    def self.lending_call?(node : Call) : Bool
      name = node.name
      !node.args.empty? && !name.starts_with?("__") &&
        (name[0].ascii_letter? || name[0] == '_') &&
        !name.ends_with?('=') && !node.block_arg
    end

    # `greet(text)`: mark each growing local argument with its slot, so a
    # String::Builder parameter gets the local's writer (call.cr), and
    # rebind the local to the writer's text after the call.
    private def lend_text_arguments(node : Call) : ASTNode?
      return nil unless program.tape_platform? && @macro_code == 0 &&
                        ris_program_code?(node) &&
                        Normalizer.lending_call?(node) &&
                        @ris_text_arg_calls.add?(node.object_id)
      lent = node.args.select do |arg|
        arg.is_a?(Var) && @ris_text_slots.has_key?(arg.name)
      end.map(&.as(Var))
      return nil if lent.empty?
      lent.each { |arg| arg.ris_text_arg = @ris_text_slots[arg.name].name }
      result = program.new_temp_var.at(node)
      lines = [Assign.new(result, node).at(node)] of ASTNode
      lent.uniq(&.name).each do |arg|
        local = Var.new(arg.name).at(arg)
        back = Call.new(Path.global("RisTextGrowth"), "__ris_take_back",
          [growing_slot(local), local.clone] of ASTNode).at(node)
        rebind = Assign.new(local.clone, back).at(node)
        @ris_growing_rebounds << rebind.object_id
        lines << rebind
      end
      lines << result.clone
      Expressions.new(lines).at(node)
    end

    def transform(node : Call)
      if node.name == "new" && node.args.size == 1 &&
         (obj = node.obj).is_a?(Path) && obj.names == ["Hash"] &&
         ris_program_code?(node)
        node.raise "infer Hash.new(default) only for a local; " \
                   "use {} of KeyType => ValueType"
      end
      if node.name == "merge!" && (info = node.ris_collection)
        probe = Call.new(nil, "__ris_collection_store",
          node.args.map(&.clone)).at(node)
        probe.ris_collection = info
        key = program.new_temp_var.at(node)
        value = program.new_temp_var.at(node)
        store = Call.new(node.obj.not_nil!.clone, "[]=",
          [key.clone, value.clone] of ASTNode).at(node)
        store.ris_collection = {info[0], "[]="}
        block = Block.new([key, value], store).at(node)
        each = Call.new(node.args.first, "each", block: block).at(node)
        return Expressions.new([probe, each, node.obj.not_nil!.clone] of ASTNode).at(node).transform(self)
      end
      # Library panic and output messages use the caller's tape too.
      # Their values are consumed here, never retained as heap Strings.
      if @macro_code == 0 && program.tape_platform? &&
         node.name.in?("puts", "print", "raise")
        node.args.map! do |arg|
          if arg.is_a?(StringInterpolation)
            TapeTextLowering.interpolate(arg)
          elsif node.name != "raise" && ris_program_code?(node) &&
                !arg.is_a?(StringLiteral) && !arg.is_a?(Splat)
            # A program prints any value as tape text, not a heap String.
            Call.new(Path.global("String").at(arg), "interpolate", arg).at(arg)
          else
            arg
          end
        end
      end
      # ris: in a program, `x.to_s` and `String.build` make tape text (a
      # Str), as interpolation does; std and the runtime keep String.
      if @macro_code == 0 && program.tape_platform? && ris_program_code?(node) &&
         @current_def.try(&.return_type).try(&.to_s) != "String"
        if node.name == "to_s" && (obj = node.obj) && node.args.empty? &&
           !node.block && !node.named_args && !node.block_arg
          return Call.new(Path.global("String").at(node), "interpolate", obj).at(node).transform(self)
        end
        if node.name == "build" && (obj = node.obj).is_a?(Path) &&
           obj.names == ["String"]
          node.obj = Path.global("String").at(obj)
        end
      end
      if lent = lend_text_arguments(node)
        return lent.transform(self)
      end
      if chain = text_append_chain(node)
        return chain.transform(self)
      end
      # String mutation spells a rebinding. Other receivers keep their
      # ordinary methods; the type test disappears after specialization.
      if program.tape_platform? && @macro_code == 0 &&
         !@ris_string_mutations.includes?(node.object_id) &&
         ((node.name == "<<" && node.args.size == 1) ||
          node.name.in?("upcase!", "downcase!", "capitalize!", "strip!",
            "lstrip!", "rstrip!", "chomp!", "reverse!", "gsub!", "sub!")) &&
         !node.block && !node.block_arg &&
         ((receiver = node.obj).is_a?(Var) || receiver.is_a?(InstanceVar))
        @ris_string_mutations << node.object_id
        method = node.name == "<<" ? "__ris_append" : node.name.rchop
        if node.name == "<<" && receiver.is_a?(InstanceVar) &&
           !@ris_growing_fields.includes?(receiver.name) &&
           !TapeScopeRuntime.runtime?(node.location)
          method = "__ris_append_field_owner"
        end
        # A String parameter is a view of the caller's text: appending
        # would grow a local copy the caller never sees.
        parameter = node.name == "<<" && receiver.is_a?(Var) &&
          ris_program_code?(node) &&
          @current_def.try(&.args.any?(&.name.==(receiver.name)))
        method = "__ris_append_parameter" if parameter
        temporary = program.new_temp_var.at(node)
        growing = !parameter && node.name == "<<" &&
          ((receiver.is_a?(Var) && @ris_growing_locals.includes?(receiver.name)) ||
           (receiver.is_a?(InstanceVar) && @ris_growing_fields.includes?(receiver.name)))
        value = if growing
                  slot = growing_slot(receiver)
                  writer = if receiver.is_a?(InstanceVar)
                             slot
                           else
                             Or.new(slot.clone, Assign.new(slot.clone,
                               Call.new(Path.global("RisTextGrowth"), "new").at(node)).at(node)).at(node)
                           end
                  Call.new(writer, "append",
                    [temporary.clone] + node.args.map(&.clone)).at(node)
                else
                  Call.new(temporary.clone, method,
                    node.args.map(&.clone)).at(node)
                end
        value.named_args = node.named_args.try &.map(&.clone)
        rebound = Assign.new(receiver.clone, value).at(node)
        @ris_growing_rebounds << rebound.object_id if growing
        node.obj = temporary.clone
        test = IsA.new(temporary.clone,
          Path.global("String").at(node)).at(node)
        return Expressions.new([
          Assign.new(temporary, receiver.clone).at(node),
          If.new(test, rebound, node).at(node),
        ] of ASTNode).at(node).transform(self)
      end
      if lowered = TapeInPlace.lower(program, node)
        return lowered.transform(self)
      end
      if TapeTextLowering.tape_block?(node)
        node.block.try(&.body.accept(TapeTextLowering.new))
      end

      # iyi: the typed group (III.4.9). The parser marked the call; whether
      # the *typed* form applies is this file's question, and a `nil` answer
      # is the method call standing as written.
      if node.iyi_group?
        expanded = expand_iyi_group(node, node.same?(@propagated_group))
        return expanded.transform(self) if expanded
      end

      # Copy enclosing def's parameters to super/previous_def without parenthesis
      case node
      when .super?, .previous_def?
        named_args = node.named_args
        if node.args.empty? && (!named_args || named_args.empty?) && !node.has_parentheses?
          if current_def = @current_def
            splat_index = current_def.splat_index
            current_def.args.each_with_index do |arg, i|
              if splat_index && i > splat_index
                # Past the splat index we must pass arguments as named arguments
                named_args = node.named_args ||= Array(NamedArgument).new
                named_args.push NamedArgument.new(arg.external_name, Var.new(arg.name))
              elsif i == splat_index
                # At the splat index we must use a splat, except the bare splat
                # parameter will be skipped
                unless arg.external_name.empty?
                  node.args.push Splat.new(Var.new(arg.name))
                end
              else
                # Otherwise it's just a regular argument
                node.args.push Var.new(arg.name)
              end
            end

            # Copy also the double splat
            if arg = current_def.double_splat
              node.args.push DoubleSplat.new(Var.new(arg.name))
            end
          end
          node.has_parentheses = true
        end
      else
        # not a special call
      end

      # Convert 'a <= b <= c' to 'a <= b && b <= c'
      if comparison?(node.name) && (obj = node.obj) && obj.is_a?(Call) && comparison?(obj.name)
        case middle = obj.args.first
        when NumberLiteral, Var, InstanceVar
          transform_many node.args
          left = obj
          right = Call.new(middle.clone, node.name, node.args).at(middle)
        else
          temp_var = program.new_temp_var
          temp_assign = Assign.new(temp_var.clone, middle).at(middle)
          left = Call.new(obj.obj, obj.name, temp_assign).at(obj.obj)
          right = Call.new(temp_var.clone, node.name, node.args).at(node)
        end
        node = And.new(left, right).at(left)
        node = node.transform self
      else
        node = super
      end

      node
    end

    def comparison?(name)
      case name
      when "<=", "<", "!=", "==", "===", ">", ">="
        true
      else
        false
      end
    end

    def transform(node : Def)
      twin = TapeInPlace.twin(program, node)
      tape_def = TapeTextLowering.tape_def?(node)
      params = node.args.map(&.name)
      node.block_arg.try { |arg| params << arg.name }
      prepare_collection_inference(node.body)
      TapeTextLowering.lower_scope(node.body, params, tape_def)
      node.body.accept(TapeTextLowering.new) if tape_def
      outer_growing = @ris_growing_locals
      outer_text_slots = @ris_text_slots
      outer_reassigned = @ris_text_reassigned
      node.body = prepare_text_growth(node.body, params)
      @current_def = node
      outer_scope, outer_params = @bound_scope, @bound_params
      @bound_scope = @macro_code == 0 && !@macro_expansion ? node.body : nil
      @bound_params = params
      node = super
      # The signature's names too: `def f(x : Hash(K, V)) : Array(T)`.
      node.return_type = node.return_type.try &.transform(self)
      node.args.each { |arg| arg.restriction = arg.restriction.try &.transform(self) }
      @bound_scope, @bound_params = outer_scope, outer_params
      @current_def = nil
      @ris_growing_locals = outer_growing
      @ris_text_slots = outer_text_slots
      @ris_text_reassigned = outer_reassigned

      # If the def has a block argument without a specification
      # and it doesn't use it, we remove it because it's useless
      # and the semantic code won't have to bother checking it
      block_arg = node.block_arg
      if !node.uses_block_arg? && block_arg
        block_arg_restriction = block_arg.restriction
        if block_arg_restriction.is_a?(ProcNotation) && !block_arg_restriction.inputs && !block_arg_restriction.output
          node.block_arg = nil
        elsif !block_arg_restriction
          node.block_arg = nil
        end
      end

      TapeScopeChecker.mark(program, node) if node.is_a?(Def) && @macro_code == 0
      return Expressions.new([node, twin.transform(self)] of ASTNode) if twin
      node
    end

    def transform(node : Macro)
      node
    end

    def transform(node : If)
      if program.tape_platform?
        TapeCheckFreeLowering.lower(node, @bound_scope, @bound_params)
      end
      node.cond = node.cond.transform(self)

      node.then = node.then.transform(self)
      then_dead_code = @dead_code

      node.else = node.else.transform(self)
      else_dead_code = @dead_code

      @dead_code = then_dead_code && else_dead_code
      node
    end

    # Convert unless to if:
    #
    # From:
    #
    #     unless foo
    #       bar
    #     else
    #       baz
    #     end
    #
    # To:
    #
    #     if foo
    #       baz
    #     else
    #       bar
    #     end
    # iyi: `read(path)!` — propagate an error member (SPEC.md III.1.2).
    #
    # From:
    #
    #     read(path)!
    #
    # To:
    #
    #     tmp = read(path)
    #     return tmp if tmp.is_a?(::Error)
    #     tmp
    #
    # No type information is needed here, and that is the point. `Error` is an
    # ordinary trait, so `is_a?` narrows the value in what follows to the
    # union's non-error members — which is exactly "if the value is a non-error
    # member, `expr!` evaluates to it". And "the enclosing function's return
    # type must already include E" is not a rule this has to enforce: it is the
    # ordinary return-type check on the `return` it just wrote.
    #
    # `::Error` rather than `Error`, so that a module of its own with that name
    # cannot change what the operator means.
    def transform(node : Propagate)
      # The standard text bang spellings rebind. Other attached bangs
      # retain iyi's error propagation (for example read(path)!).
      if program.tape_platform? && (call = node.exp).is_a?(Call) &&
         call.iyi_banged? && !call.block && !call.block_arg &&
         call.name.in?("upcase", "downcase", "capitalize", "strip",
           "lstrip", "rstrip", "chomp", "reverse", "gsub", "sub") &&
         ((receiver = call.obj).is_a?(Var) || receiver.is_a?(InstanceVar))
        plain = call.clone
        plain.iyi_banged = false
        return Assign.new(receiver.clone, plain).at(node).transform(self)
      end
      if (group = node.exp).is_a?(Call) && group.iyi_group?
        @propagated_group = group
      end
      exp = node.exp.transform(self)
      temp_var = program.new_temp_var

      assign = Assign.new(temp_var.clone, exp).at(node)
      check = IsA.new(temp_var.clone, Path.global(["Error"]).at(node)).at(node)
      # A `group do ... end!` that kept the general form answers its block's
      # last expression, and the refusal of a `!` with nothing to propagate
      # says so (`MainVisitor#check_error_union_operand`).
      check.error_construct = exp.is_a?(Call) && exp.iyi_group? ? "end!" : "!"
      if exp.is_a?(Call) && exp.iyi_banged? && (receiver = exp.obj) && exp.args.empty? && !exp.block
        check.iyi_bang_call = {exp.name, receiver.to_s}
      end
      returned = Return.new(temp_var.clone).at(node)
      returned.from_propagate = true
      propagate = If.new(check, returned).at(node)

      Expressions.new([assign, propagate, temp_var.clone] of ASTNode).at(node)
    end

    # iyi: the `group do ... end!` whose `!` is being expanded: the typed
    # group reads its values before the join when its answer is propagated.
    @propagated_group : Call?

    # iyi: `read_port().or(8080)` and `read_port().or_panic` (SPEC.md III.1.3).
    #
    # From:
    #
    #     read_port().or(8080)          read_port().or_panic
    #
    # To:
    #
    #     tmp = read_port()             tmp = read_port()
    #     if tmp.is_a?(::Error)         if tmp.is_a?(::Error)
    #       8080                          ::raise tmp.message
    #     else                          else
    #       tmp                           tmp
    #     end                           end
    #
    # Same trick as `Propagate` above, and for the same reason: `is_a?` already
    # narrows both ways, so the result type falls out instead of being computed.
    # `.or` yields the default unioned with the non-error members; `.or_panic`
    # yields the non-error members alone, because `raise` is `NoReturn`.
    #
    # `tmp.message` is only reached where `tmp` has been narrowed to the error
    # members, and every one of those implements `Error` — so by II.1 the union
    # implements it too and `message` dispatches without either branch of this
    # having to know which error it holds.
    #
    # The default is evaluated only when there is an error to recover from,
    # which is what a reader of `||` would expect.
    #
    # `::raise` *is* the panic: III.1.4 is built, so the unwrap of this
    # design dies at the task boundary carrying the error's `message`.
    # The line the earlier revision promised would change changed by
    # not needing to.
    def transform(node : Recover)
      exp = node.exp.transform(self)
      temp_var = program.new_temp_var

      assign = Assign.new(temp_var.clone, exp).at(node)
      check = IsA.new(temp_var.clone, Path.global(["Error"]).at(node)).at(node)
      check.error_construct = node.panic? ? ".or_panic" : ".or"

      recovery =
        if default = node.default
          default.transform(self)
        else
          Call.global("raise", Call.new(temp_var.clone, "message").at(node)).at(node)
        end

      value = If.new(check, recovery, temp_var.clone).at(node)

      Expressions.new([assign, value] of ASTNode).at(node)
    end

    def transform(node : Unless)
      If.new(node.cond, node.else, node.then).transform(self).at(node)
    end

    # Convert until to while:
    #
    # From:
    #
    #    until foo
    #      bar
    #    end
    #
    # To:
    #
    #    while !foo
    #      bar
    #    end
    # ris: how deep in `{% %}` code the transform is; its blocks run in the
    # compiler and get no tape marks.
    property macro_code = 0

    def transform(node : MacroExpression)
      @macro_code += 1
      result = super
      @macro_code -= 1
      result
    end

    def transform(node : MacroIf)
      @macro_code += 1
      result = super
      @macro_code -= 1
      result
    end

    def transform(node : MacroFor)
      @macro_code += 1
      result = super
      @macro_code -= 1
      result
    end

    def transform(node : ClassDef)
      outer_locals, outer_slots = @ris_growing_locals, @ris_text_slots
      @ris_growing_locals = Set(String).new
      @ris_text_slots = {} of String => Var
      outer_fields = @ris_growing_fields
      @ris_growing_fields = Set(String).new
      if program.tape_platform? && @macro_code == 0 &&
         !TapeScopeRuntime.runtime?(node.location)
        scan = GrowingTextScan.new(methods: true)
        node.body.accept(scan)
        @ris_growing_fields = scan.fields - scan.non_text_fields
        @ris_growing_fields.each { |name| program.ris_growing_field_names << name }
        declarations = @ris_growing_fields.flat_map do |name|
          slot = growing_slot(InstanceVar.new(name).at(node))
          type = Path.global("RisTextGrowth").at(node)
          declaration = TypeDeclaration.new(slot, type,
            Call.new(type.clone, "new").at(node)).at(node)
          declaration.ris_text_companion = true
          # Keep the legacy helper ABI: a statement returning Nil. A
          # reference result would give the old shrink analysis another
          # receiver/result alias through its scope-result wrapper.
          field = InstanceVar.new(name).at(node)
          rewind = Assign.new(field.clone,
            Call.new(slot.clone, "__ris_text_reset", field).at(node)).at(node)
          reset = Def.new("__ris_text_reset_#{name.lchop('@')}", [] of Arg,
            Expressions.new([rewind, NilLiteral.new.at(node)] of ASTNode)).at(node)
          [declaration, reset] of ASTNode
        end
        node.body = Expressions.new(declarations + [node.body]).at(node) unless declarations.empty?
      end
      outer = @scanners
      @scanners = [] of String
      body = node.body
      (body.is_a?(Expressions) ? body.expressions : [body]).each do |exp|
        if exp.is_a?(TypeDeclaration) && (var = exp.var).is_a?(InstanceVar)
          @scanners << var.name.lchop('@') if scanner_path?(exp.declared_type)
        elsif exp.is_a?(Def) && exp.name == "initialize"
          # A field with no declaration, typed by `@sc = Str::Scanner.new`.
          init = exp.body
          (init.is_a?(Expressions) ? init.expressions : [init]).each do |line|
            next unless line.is_a?(Assign) && (target = line.target).is_a?(InstanceVar)
            value = line.value
            next unless value.is_a?(Call) && value.name == "new" && scanner_path?(value.obj)
            name = target.name.lchop('@')
            @scanners << name unless @scanners.includes?(name)
          end
        end
      end
      node = super
      @scanners = outer
      @ris_growing_fields = outer_fields
      @ris_growing_locals, @ris_text_slots = outer_locals, outer_slots
      node
    end

    private def scanner_path?(type) : Bool
      type.is_a?(Path) && type.names == ["String", "Scanner"]
    end

    def transform(node : ModuleDef)
      outer_locals, outer_slots = @ris_growing_locals, @ris_text_slots
      @ris_growing_locals = Set(String).new
      @ris_text_slots = {} of String => Var
      outer = @scanners
      @scanners = [] of String
      node = super
      @scanners = outer
      @ris_growing_locals, @ris_text_slots = outer_locals, outer_slots
      node
    end

    def transform(node : While)
      if program.tape_platform? && @macro_code == 0 && @current_def &&
         (lowered = TapeCursorLowering.lower(node, @scanners))
        return lowered.transform(self)
      end
      # Only where the prelude has the tape, whose `__loop_fetch` it calls.
      if program.tape_platform?
        TapeCheckFreeLowering.lower(node, @bound_scope, @bound_params)
      end
      node = super
      TapeScopeChecker.mark(program, node) if node.is_a?(While) && @macro_code == 0
      node
    end

    def transform(node : Until)
      node = super
      not_exp = Not.new(node.cond).at(node.cond)
      While.new(not_exp, node.body).at(node)
    end

    # Constants retain static literals after parentheses are normalized.
    def transform(node : TypeDeclaration)
      super
      value = node.value
      if node.var.is_a?(Path) && value.is_a?(Call) && value.tape_literal? &&
         node.declared_type.to_s != "String"
        node.value = value.args.first
      end
      value = node.value
      if value && !value.simple_literal? &&
         program_initializer?(node.var, node)
        node.value = program_initializer(value)
      end
      if node.value && node.var.is_a?(Var) &&
         (reset = text_reset(node.var, node))
        Expressions.new([node, reset, node.var.clone] of ASTNode).at(node)
      else
        node
      end
    end

    private def program_initializer?(target : ASTNode, node : ASTNode) : Bool
      program.tape_platform? && tape_text?(node) &&
        target.is_a?(Path)
    end

    private def program_initializer(value : ASTNode) : ASTNode
      call = Call.new(nil, "__ris_program_init",
        block: Block.new([] of Var, value), global: true).at(value)
      call.program_initializer = true
      call
    end

    # Checks if the right hand side is dead code.
    def transform(node : Assign)
      super
      value = node.value
      if node.target.is_a?(Path) && value.is_a?(Call) && value.tape_literal?
        node.value = value.args.first
      end

      if program_initializer?(node.target, node) &&
         !node.value.simple_literal?
        node.value = program_initializer(node.value)
      end
      if @dead_code
        node.value
      elsif !@ris_growing_rebounds.includes?(node.object_id) &&
            (reset = text_reset(node.target, node))
        Expressions.new([node, reset, node.target.clone] of ASTNode).at(node)
      else
        node
      end
    end

    private def text_reset(target : ASTNode, at : ASTNode) : ASTNode?
      return nil unless program.tape_platform? && @macro_code == 0 &&
                        !TapeScopeRuntime.runtime?(at.location)
      if target.is_a?(Var) && @ris_growing_locals.includes?(target.name)
        unless @ris_text_reassigned.includes?(target.name)
          return Assign.new(growing_slot(target), growing_initializer(target)).at(at)
        end
        slot = growing_slot(target)
        writer = Or.new(slot.clone, Assign.new(slot.clone,
          Call.new(Path.global("RisTextGrowth"), "new").at(at)).at(at)).at(at)
        reset = Assign.new(target.clone,
          Call.new(writer, "__ris_text_reset", target.clone).at(at)).at(at)
        # Non-String locals keep the old lowering and never acquire a
        # companion merely because their << is an Array/Builder method.
        return If.new(IsA.new(target.clone, Path.global("String")).at(at), reset).at(at)
      end
      return nil unless target.is_a?(InstanceVar) && @current_def
      if @ris_growing_fields.includes?(target.name)
        reset = Assign.new(target.clone,
          Call.new(growing_slot(target), "__ris_text_reset",
            target.clone).at(at)).at(at)
        return reset
      end
      return nil unless program.ris_growing_field_names.includes?(target.name) &&
                        @current_def.try(&.name) != "initialize"
      method = "__ris_text_reset_#{target.name.lchop('@')}"
      receiver = Var.new("self").at(at)
      reset = If.new(RespondsTo.new(receiver.clone, method).at(at),
        Call.new(receiver, method).at(at)).at(at)
      reset
    end

    def transform(node : MultiAssign)
      node = super
      resets = node.targets.compact_map do |target|
        target = target.exp if target.is_a?(Splat)
        text_reset(target, node)
      end
      return node if resets.empty?
      result = program.new_temp_var.at(node)
      Expressions.new([Assign.new(result.clone, node).at(node)] +
        resets + [result.clone]).at(node)
    end

    # Convert `a += b` to `a = a + b`
    def transform(node : OpAssign)
      probe = nil
      if info = node.ris_collection
        target = node.target.as(Call)
        args = target.args.map(&.clone)
        args << (target.ris_hash_default.try(&.clone) || node.value.clone)
        probe = Call.new(nil, "__ris_collection_store", args).at(node)
        probe.ris_collection = info
      end
      super

      target = node.target
      result = if target.is_a?(Call)
        if target.name == "[]"
          transform_op_assign_index(node, target)
        else
          transform_op_assign_call(node, target)
        end
      else
        transform_op_assign_simple(node, target)
      end
      probe ? Expressions.new([probe, result] of ASTNode).at(node) : result
    end

    def transform_op_assign_call(node, target)
      obj = target.obj.not_nil!

      # Convert
      #
      #     a.exp += b
      #
      # To
      #
      #     tmp = a
      #     tmp.exp=(tmp.exp + b)
      case obj
      when Var, InstanceVar, ClassVar, .simple_literal?
        tmp = obj
      else
        tmp = program.new_temp_var

        # (1) = tmp = a
        assign = Assign.new(tmp, obj).at(node)
      end

      # (2) = tmp.exp
      call = Call.new(tmp.clone, target.name).at(node)
      call.name_location = node.name_location

      case node.op
      when "||"
        # Special: tmp.exp || tmp.exp=(b)
        #
        # (3) = tmp.exp=(b)
        right = Call.new(tmp.clone, "#{target.name}=", node.value).at(node)
        right.name_location = node.name_location

        # (4) = (2) || (3)
        call = Or.new(call, right).at(node)
      when "&&"
        # Special: tmp.exp && tmp.exp=(b)
        #
        # (3) = tmp.exp=(b)
        right = Call.new(tmp.clone, "#{target.name}=", node.value).at(node)
        right.name_location = node.name_location

        # (4) = (2) && (3)
        call = And.new(call, right).at(node)
      else
        # (3) = (2) + b
        call = Call.new(call, node.op, node.value).at(node)
        call.name_location = node.name_location

        # (4) = tmp.exp=((3))
        call = Call.new(tmp.clone, "#{target.name}=", call).at(node)
        call.name_location = node.name_location
      end

      # (1); (4)
      if assign
        Expressions.new([assign, call] of ASTNode).at(node)
      else
        call
      end
    end

    def transform_op_assign_index(node, target)
      obj = target.obj.not_nil!

      # Convert
      #
      #     a[exp1, exp2, ...] += b
      #
      # To
      #
      #     tmp = a
      #     tmp1 = exp1
      #     tmp2 = exp2
      #     ...
      #     tmp.[]=(tmp1, tmp2, ..., tmp[tmp1, tmp2, ...] + b)
      tmp_args = target.args.map { program.new_temp_var(node).as(ASTNode) }
      tmp = program.new_temp_var(node)

      # (1) = tmp1 = exp1; tmp2 = exp2; ...; tmp = a
      tmp_assigns = Array(ASTNode).new(tmp_args.size + 1)
      tmp_args.each_with_index do |var, i|
        # For simple literals we don't need a temp variable
        arg = target.args[i]
        if arg.simple_literal?
          tmp_args[i] = arg
        else
          tmp_assigns << Assign.new(var.clone, arg).at(node)
        end
      end

      case obj
      when Var, InstanceVar, ClassVar, .simple_literal?
        # Nothing
        tmp = obj
      else
        tmp_assigns << Assign.new(tmp, obj).at(node)
      end

      case node.op
      when "||"
        # Special: tmp[tmp1, tmp2, ...]? || (tmp[tmp1, tmp2, ...] = b)
        #
        # (2) = tmp[tmp1, tmp2, ...]?
        call = Call.new(tmp.clone, "[]?", tmp_args).at(node)
        call.name_location = node.name_location

        # (3) = tmp[tmp1, tmp2, ...] = b
        args = Array(ASTNode).new(tmp_args.size + 1)
        tmp_args.each { |arg| args << arg.clone }
        args << node.value
        right = Call.new(tmp.clone, "[]=", args).at(node)
        right.name_location = node.name_location
        right.ris_collection = node.ris_collection

        # (3) = (2) || (4)
        call = Or.new(call, right).at(node)
      when "&&"
        # Special: tmp[tmp1, tmp2, ...]? && (tmp[tmp1, tmp2, ...] = b)
        #
        # (2) = tmp[tmp1, tmp2, ...]?
        call = Call.new(tmp.clone, "[]?", tmp_args).at(node)
        call.name_location = node.name_location

        # (3) = tmp[tmp1, tmp2, ...] = b
        args = Array(ASTNode).new(tmp_args.size + 1)
        tmp_args.each { |arg| args << arg.clone }
        args << node.value
        right = Call.new(tmp.clone, "[]=", args).at(node)
        right.name_location = node.name_location
        right.ris_collection = node.ris_collection

        # (3) = (2) && (4)
        call = And.new(call, right).at(node)
      else
        # (2) = tmp[tmp1, tmp2, ...]
        call = if default = target.ris_hash_default
                 Call.new(tmp.clone, "fetch", tmp_args + [default.clone.as(ASTNode)]).at(node)
               else
                 Call.new(tmp.clone, "[]", tmp_args).at(node)
               end
        call.name_location = node.name_location

        # (3) = (2) + b
        call = Call.new(call, node.op, node.value).at(node)
        call.name_location = node.name_location

        # (4) tmp.[]=(tmp1, tmp2, ..., (3))
        args = Array(ASTNode).new(tmp_args.size + 1)
        tmp_args.each { |arg| args << arg.clone }
        args << call
        call = Call.new(tmp.clone, "[]=", args).at(node)
        call.name_location = node.name_location
        call.ris_collection = node.ris_collection
      end

      # (1); (4)
      if tmp_assigns.empty?
        call
      else
        exps = Array(ASTNode).new(tmp_assigns.size + 2)
        exps.concat(tmp_assigns)
        exps << call

        Expressions.new(exps).at(node)
      end
    end

    def transform_op_assign_simple(node, target)
      case node.op
      when "&&"
        # (1) a = b
        assign = Assign.new(target, node.value).at(node)

        # a && (1)
        And.new(target.clone, assign).at(node)
      when "||"
        # (1) a = b
        assign = Assign.new(target, node.value).at(node)

        # a || (1)
        Or.new(target.clone, assign).at(node)
      else
        # (1) = a + b
        call = Call.new(target, node.op, node.value).at(node)
        call.name_location = node.name_location

        # a = (1)
        Assign.new(target.clone, call).at(node)
      end
    end

    # Runtime text in ris is a view of static bytes or a tape builder.
    # Macro code and annotation arguments remain compiler metadata.
    private def tape_text?(node : ASTNode) : Bool
      file = node.location.try(&.original_filename)
      # ris: every program file, .ri or .iyi, has no heap: its text is tape
      # text. std, the runtime and artifacts keep String until migrated.
      @macro_code == 0 && !!file &&
        (file.ends_with?(".ri") || (file.ends_with?(".iyi") && ris_program_code?(node))) &&
        !TapePointerCheckerLibrary.library?(node.location)
    end

    def transform(node : Annotation)
      node
    end

    private def heap_literal(node : ASTNode) : ASTNode
      value = node.transform(self)
      if value.is_a?(Call) && value.tape_literal?
        value.args.first
      else
        value
      end
    end

    def transform(node : ArrayLiteral)
      if node.elements.empty? && !node.of && !node.name
        node.raise "for empty arrays use '[] of ElementType'"
      end
      return super if node.name
      node.elements.map! { |value| heap_literal(value) }
      node.of = node.of.try &.transform(self)
      node
    end

    def transform(node : TupleLiteral)
      node.elements.map! { |value| heap_literal(value) }
      node
    end

    def transform(node : HashLiteral)
      if node.entries.empty? && !node.of && !node.name
        node.raise "for empty hashes use '{} of KeyType => ValueType'"
      end
      return super if node.name
      node.entries.map! do |entry|
        HashLiteral::Entry.new(
          heap_literal(entry.key), heap_literal(entry.value))
      end
      node.name = node.name.try &.transform(self)
      node.of = node.of.try do |entry|
        HashLiteral::Entry.new(
          entry.key.transform(self), entry.value.transform(self))
      end
      node
    end

    def transform(node : NamedTupleLiteral)
      node.entries.map! do |entry|
        NamedTupleLiteral::Entry.new(entry.key, heap_literal(entry.value))
      end
      node
    end

    def transform(node : StringLiteral)
      return node unless tape_text?(node)
      call = Call.new(Path.global(["String"]), "view", [node] of ASTNode).at(node)
      call.tape_literal = true
      call
    end

    # ris: in a program, `Hash` and `Array` name the tape Hsh and Ary, so
    # Ruby's names work and stay off the heap; std keeps the heap types.
    def transform(node : Path)
      if @macro_code == 0 && node.names.size == 1 && !node.global? &&
         ris_program_code?(node)
        case node.names.first
        when "Hash"  then return Path.global("Hash").at(node)
        when "Array" then return Path.global("Array").at(node)
        when "String" then return Path.global("String").at(node)
        end
      end
      node
    end

    def transform(node : StringInterpolation)
      if tape_text?(node)
        return TapeTextLowering.interpolate(node).transform(self)
      end
      # If the interpolation has just one string literal inside it,
      # return that instead of an interpolation
      if node.expressions.size == 1
        first = node.expressions.first
        return first if first.is_a?(StringLiteral)
      end

      super
    end

    # Turn block argument unpacking to multi assigns at the beginning
    # of a block.
    #
    # So this:
    #
    #    foo do |(x, y), z|
    #      x + y + z
    #    end
    #
    # is transformed to:
    #
    #    foo do |__temp_1, z|
    #      x, y = __temp_1
    #      x + y + z
    #    end
    def transform(node : Block)
      if program.tape_platform? && @macro_code == 0
        slots = node.args.select { |arg| @ris_growing_locals.includes?(arg.name) }.map do |arg|
          Assign.new(growing_slot(arg),
            growing_initializer(arg)).at(arg).as(ASTNode)
        end
        node.body = Expressions.new(slots + [node.body]).at(node) unless slots.empty?
      end
      node = super
      TapeScopeChecker.mark(program, node) if node.is_a?(Block) && @macro_code == 0

      unpacks = node.unpacks
      return node unless unpacks

      # as `node` is mutated in-place, ensure it can only be mutated once
      # we consider a block to be mutated if any unpack already has a
      # corresponding block parameter with a name (as the fictitious packed
      # parameters have empty names)
      return node if unpacks.any? { |index, _| !node.args[index].name.empty? }

      extra_expressions = [] of ASTNode
      next_unpacks = [] of {String, Expressions}

      unpacks.each do |index, expressions|
        temp_name = program.new_temp_var_name
        node.args[index] = Var.new(temp_name).at(node.args[index])

        extra_expressions << block_unpack_multiassign(temp_name, expressions, next_unpacks)
      end

      if next_unpacks
        while next_unpack = next_unpacks.shift?
          var_name, expressions = next_unpack

          extra_expressions << block_unpack_multiassign(var_name, expressions, next_unpacks)
        end
      end

      body = node.body
      case body
      when Nop
        node.body = Expressions.new(extra_expressions).at(node.body)
      when Expressions
        body.expressions = extra_expressions + body.expressions
      else
        extra_expressions << node.body
        node.body = Expressions.new(extra_expressions).at(node.body)
      end

      node
    end

    private def block_unpack_multiassign(var_name, expressions, next_unpacks)
      targets = expressions.expressions.map do |exp|
        case exp
        when Var
          exp
        when Underscore
          exp
        when Splat
          exp
        when Expressions
          next_temp_name = program.new_temp_var_name

          next_unpacks << {next_temp_name, exp}

          Var.new(next_temp_name).at(exp)
        else
          raise "BUG: unexpected block var #{exp} (#{exp.class})"
        end
      end
      values = [Var.new(var_name).at(expressions)] of ASTNode
      MultiAssign.new(targets, values).at(expressions)
    end

    def transform(node : Union)
      if node.singleton?
        # If the union has just one type, return that instead of a union
        node.types.first
      else
        super
      end
    end
  end
end

require "./ris_collection_inference"

