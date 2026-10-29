module Iyi
  class Program
    property? ris_default_hash_defined = false
  end

  class Normalizer
    # A value carries its default across aliases and method boundaries.
    # Keep this ris runtime addition out of the inherited iyi prelude.
    RIS_DEFAULT_HASH = <<-'RUNTIME'
      @[OnTape]
      struct RisDefaultHash(K, V)
        @entries : Hash(K, V)
        @default : V

        def initialize(@default : V)
          @entries = Hash(K, V).new
        end

        def [](key : K) : V
          @entries.fetch(key, @default)
        end

        def []?(key : K) : V?
          @entries[key]?
        end

        def []=(key : K, value : V) : V
          @entries[key] = value
        end

        def size : Int32
          @entries.size
        end

        def empty? : Bool
          @entries.empty?
        end

        def keys : Array(K)
          @entries.keys
        end

        def values : Array(V)
          @entries.values
        end

        def each(& : K, V ->)
          @entries.each { |key, value| yield key, value }
          self
        end

        def has_key?(key : K) : Bool
          @entries.has_key?(key)
        end

        def fetch(key : K, default : D) : V | D forall D
          @entries.fetch(key, default)
        end

        def delete(key : K) : V?
          @entries.delete(key)
        end

        def clear
          @entries.clear
          self
        end
      end
      RUNTIME

    def prepare_default_hash(node : Expressions) : Nil
      return if program.ris_default_hash_defined? ||
                     !ris_program_code?(node)
      node.at(node.location)
      program.ris_default_hash_defined = true
      parser = program.new_parser(RIS_DEFAULT_HASH)
      parser.filename = "__ris_default_hash.cr"
      runtime = parser.parse
      node.expressions.unshift(runtime)
    end
  end
end
