module Iyi
  class Normalizer
    # Run before lowering, while local names and source order are intact.
    def prepare_collection_inference(body : ASTNode)
      return unless ris_program_code?(body)
      scan = RisCollectionScan.new(program)
      body.accept(scan)
      scan.finish
    end

    class RisCollectionScan < Visitor
      record Slot, id : String, kind : String, origin : ASTNode,
        default : Var? = nil
      @slots = {} of String => Slot
      @stored = Set(String).new
      @all_slots = [] of Slot

      def initialize(@program : Program)
      end

      def finish
        @all_slots.each do |slot|
          refuse(slot.origin, slot) unless @stored.includes?(slot.id)
        end
      end

      private def refuse(node, slot)
        form = slot.kind == "array" ? "[] of ElementType" :
          "{} of KeyType => ValueType"
        node.raise "first store must precede every use; use #{form}"
      end

      private def deferred(slot, index)
        node = TypeOf.new([] of ASTNode).at(slot.origin)
        node.ris_collection = {slot.id, "type:#{index}"}
        node
      end

      def visit(node : Assign)
        target = node.target
        value = node.value
        kind = case value
               when ArrayLiteral
                 "array" if value.elements.empty? && !value.of
               when HashLiteral
                 "hash" if value.entries.empty? && !value.of
               when Call
                 if value.name == "new" && value.args.size == 1 &&
                    (path = value.obj).is_a?(Path) && path.names == ["Hash"]
                   "hash"
                 end
               end
        if kind
          unless target.is_a?(Var)
            form = kind == "array" ? "[] of ElementType" :
              "{} of KeyType => ValueType"
            node.raise "for empty collections use '#{form}'"
          end
          id = @program.new_temp_var.name
          default = @program.new_temp_var.at(value) if value.is_a?(Call)
          slot = Slot.new(id, kind, value, default)
          @slots[target.name] = slot
          @all_slots << slot
          case value
          when ArrayLiteral
            value.of = deferred(slot, 0)
          when HashLiteral
            value.of = HashLiteral::Entry.new(
              deferred(slot, 0), deferred(slot, 1))
          when Call
            default = default.not_nil!
            value.args.first.accept(self)
            of_value = deferred(slot, 1)
            of_value.expressions << default.clone
            generic = Generic.new(Path.global("Hash"),
              [deferred(slot, 0), of_value] of ASTNode).at(value)
            node.value = Expressions.new([
              Assign.new(default, value.args.first).at(value),
              Call.new(generic, "with_default", default.clone).at(value),
            ] of ASTNode).at(value)
          end
          return false
        end
        if target.is_a?(Var) && (slot = @slots[target.name]?)
          value.accept(self)
          node.ris_collection = {slot.id, "assign:#{slot.kind}"}
          @stored << slot.id
          return false
        end
        true
      end

      def visit(node : OpAssign)
        if (target = node.target).is_a?(Call) && target.name == "[]" &&
           (obj = target.obj).is_a?(Var) && (slot = @slots[obj.name]?)
          if slot.kind == "hash" && (node.op == "||" || slot.default)
            target.args.each &.accept(self)
            node.value.accept(self)
            target.ris_hash_default = slot.default
            node.ris_collection = {slot.id, "[]="}
            @stored << slot.id
            return false
          end
        end
        true
      end

      def visit(node : Call)
        if (obj = node.obj).is_a?(Var) && (slot = @slots[obj.name]?)
          if node.name == "[]" && (default = slot.default)
            node.args.each &.accept(self)
            node.ris_collection = {slot.id, "default:index"}
            @stored << slot.id
            return false
          end
          store = slot.kind == "array" ?
            {"<<", "push", "concat"}.includes?(node.name) :
            {"[]=", "merge!"}.includes?(node.name)
          if store
            node.args.each &.accept(self)
            node.ris_collection = {slot.id, node.name}
            @stored << slot.id
            node.block.try &.accept(self)
            return false
          end
        end
        true
      end

      def visit(node : Var)
        if (slot = @slots[node.name]?) && !@stored.includes?(slot.id)
          refuse(node, slot)
        end
        false
      end

      def visit(node : Block)
        outer = @slots.dup
        node.args.each { |arg| @slots.delete(arg.name) }
        node.body.accept(self)
        @slots = outer
        false
      end

      def visit(node : Def | ClassDef | ModuleDef | Macro)
        false
      end

      def visit(node : ASTNode)
        true
      end
    end
  end
end
