require "./program"

module Iyi::OpenTravel
  def self.mark(program : Program) : Nil
    return if ENV["IYI_OPEN_TRAVEL"]? == "off"

    Walk.new(program).run
  end

  # The call graph of this build's instantiated defs, in the one direction the
  # question needs: from a callee to the defs that call it.
  private class Walk
    # Instances by object id, so an instance reached twice is walked once.
    @seen = {} of UInt64 => Def
    # Callee instance id => the instances that call it.
    @callers = {} of UInt64 => Array(Def)
    # Instance ids whose machine code answers for an open set.
    @open = Set(UInt64).new

    def initialize(@program : Program)
    end

    def run : Nil
      collect_types @program
      @program.file_modules.each_value { |file_module| collect_types file_module }
      propagate
      record
    end

    # Every type this build made, and every def instance on it.
    #
    # The same walk `TypedDefProcessor` does for the tools, written out here
    # because this one has no target location to stop at: a module's method is
    # instantiated on the *including* type, so the instance that matters is
    # never on the type that declared it — `Kemal::InitHandler@HTTP::Handler#
    # call_next` is `Kemal::InitHandler`'s to carry and `HTTP::Handler`'s to
    # have written.
    private def collect_types(type : Type) : Nil
      if type.is_a?(NamedType) || type.is_a?(Program) || type.is_a?(FileModule)
        type.types?.try &.each_value { |inner| collect_types inner }
      end

      if type.is_a?(GenericType)
        type.each_instantiated_type { |instance| collect_types instance }
      end

      collect_types type.metaclass if type.metaclass != type

      return unless type.is_a?(DefInstanceContainer)
      type.def_instances.each_value { |instance| collect_instance instance }
    end

    # One instance's body, read once: whether it holds an open dispatch, and
    # which instances it calls.
    #
    # A callee is walked from here as well, because an instance is not always in
    # a type's `def_instances` — a block-taking one is instantiated per call site
    # and cached nowhere — and a closure that stopped at those would lose every
    # caller behind one.
    #
    # A worklist rather than recursion: the depth here is the depth of the
    # program's call graph, and a parser's descent is deeper than a stack this
    # runs on cares to be.
    private def collect_instance(root : Def) : Nil
      pending = [root]
      until pending.empty?
        instance = pending.pop
        next if @seen.has_key?(instance.object_id)
        @seen[instance.object_id] = instance

        calls = Calls.new
        instance.body.accept calls

        @open << instance.object_id if calls.open?

        calls.callees.each do |callee|
          # A def read from a `.iyimod` has no body here: its machine code is in
          # somebody else's object code, and its own artifact answered this
          # question when it was written.
          next if callee.iyi_from_artifact?
          # Every other callee is followed, the library's included: while a
          # module's unit is emitted, what it calls is copied into that unit
          # (IV.1g), so a dispatch inside a library method is a dispatch inside
          # the artifact.

          (@callers[callee.object_id] ||= [] of Def) << instance
          pending << callee
        end
      end
    end

    # A caller of an open instance is open: its object code calls the producer's
    # copy by name, and that copy holds the producer's set.
    private def propagate : Nil
      # `IYI_OPEN_TRAVEL=trace` prints the seeds — the instantiations that hold
      # a dispatch over an open set — and then what the closure reached. A
      # boundary that suddenly carries a body as source is read here first.
      trace = ENV["IYI_OPEN_TRAVEL"]? == "trace"
      if trace
        @open.each do |id|
          instance = @seen[id]?
          STDERR.puts "open-dispatch seed: #{describe(instance)}" if instance
        end
      end

      queue = @open.to_a
      until queue.empty?
        callee = queue.pop
        @callers[callee]?.try &.each do |caller|
          next if @open.includes?(caller.object_id)
          @open << caller.object_id
          queue << caller.object_id
          if trace
            STDERR.puts "open-dispatch caller: #{describe(caller)} -> #{describe(@seen[callee]?)}"
          end
        end
      end
    end

    private def describe(instance : Def?) : String
      return "?" unless instance
      "#{instance.owner}##{instance.name} (#{instance.location})"
    end

    # The mark goes on the def as it was *written*, which is the one an artifact
    # writer holds. An instance with no origin is this compiler's own — a
    # `Primitive`, a synthesized `new` — and has no written body to travel.
    private def record : Nil
      @open.each do |id|
        instance = @seen[id]?
        next unless instance

        origin = instance.iyi_origin || instance
        origin.iyi_open_travel = true
      end
    end
  end

  # The calls in one body: whether any answered out of an open set, and every
  # instance they reach.
  private class Calls < Visitor
    getter callees = [] of Def
    @open = false

    def open?
      @open
    end

    def visit(node : Call)
      @open = true if node.iyi_open_dispatch?
      node.target_defs.try &.each { |callee| @callees << callee }
      true
    end

    def visit(node)
      true
    end
  end
end
