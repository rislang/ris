module Iyi
  class MainVisitor
    getter ris_collection_types = {} of String => Array(TypeOf)

    protected def ris_collection_nodes(id : String) : Array(TypeOf)?
      @ris_collection_types[id]? || parent.try &.ris_collection_nodes(id)
    end

    private def ris_infer_store(node : ASTNode, values : Array(ASTNode))
      return unless info = node.ris_collection
      id, kind = info
      return unless types = ris_collection_nodes(id)
      values.each &.accept(self)
      values.each_with_index do |value, index|
        next unless expected = types[index]?
        if prior = expected.type?
          if (actual = value.type?) && prior != actual
            form = types.size == 1 ? "[] of T" : "{} of K => V"
            node.raise "first store inferred #{prior}, later store has " \
                       "#{actual}; use #{form} for explicit types"
          end
        elsif expected.expressions.empty?
          expected.expressions << value
          expected.bind_to(value)
        end
      end
    end

    private def ris_infer_call(node : Call)
      return unless info = node.ris_collection
      id, kind = info
      values = case kind
               when "<<", "push", "[]=", "__ris_collection_store"
                 node.args.map(&.clone)
               when "default:index"
                 [node.args.first.clone] of ASTNode
               when "concat"
                 [Call.new(node.args.first.clone, "first").at(node)] of ASTNode
               when "merge!"
                 other = node.args.first
                 [Call.new(other.clone, "keys").at(node),
                  Call.new(other.clone, "values").at(node)].map do |column|
                   Call.new(column, "first").at(node).as(ASTNode)
                 end
               else
                 return
               end
      ris_infer_store(node, values)
    end
  end
end
