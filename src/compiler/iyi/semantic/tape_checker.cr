# PROTOTYPE (ris, step B): the type-level half of tape safety.
#
# A tape type is a struct marked `@[OnTape]`. Its storage - the bytes of a
# `Tape::String`, the elements of a `Tape::Array` - is the current fiber's tape,
# and is reclaimed when the `Tape.use` that made it ends. So a tape value
# may live in locals, in parameters, in other tape values and in the tape
# itself, and nowhere that can outlive the scope:
#
# * not in a field of a type that is not a tape type: a class instance, or
#   a struct that is not `@[OnTape]` (which could be stored anywhere),
# * not in a class variable,
# * not as a type argument of a generic that is not a tape type:
#   `Array(Resp)` is a class with a `Pointer(Resp)` field, `Channel(Resp)`
#   crosses fibers.
#
# Each is a fact about types, so this runs once over every type after the
# main pass, the way `RecursiveStructChecker` does. The flow half - a block
# capturing a tape value, a `Tape.use` handing one out - is in
# `TapeLifetimeChecker`; proc captures are checked during cleanup.
class Iyi::TapeChecker
  @program : Program

  def initialize(@program)
  end

  def self.tape?(program : Program, type : Type) : Bool
    type = type.remove_typedef
    if type.is_a?(GenericClassInstanceType)
      return !type.generic_type.annotation(program.tape_annotation).nil?
    end
    return false unless type.is_a?(Annotatable)
    !type.annotation(program.tape_annotation).nil?
  end

  # The tape type *type* holds, directly or through a union, a tuple or a
  # pointer, or nil.
  def self.tape_in(program : Program, type : Type, visiting = Set(Type).new) : Type?
    return nil unless visiting.add?(type)
    return type if tape?(program, type)
    case type
    when UnionType
      type.union_types.each { |member| tape_in(program, member, visiting).try { |found| return found } }
    when TupleInstanceType
      type.tuple_types.each { |member| tape_in(program, member, visiting).try { |found| return found } }
    when NamedTupleInstanceType
      type.entries.each { |entry| tape_in(program, entry.type, visiting).try { |found| return found } }
    when PointerInstanceType
      return tape_in(program, type.element_type, visiting)
    when GenericClassInstanceType
      type.type_vars.each_value do |type_var|
        if type_var.is_a?(Var) && (var_type = type_var.type?)
          tape_in(program, var_type, visiting).try { |found| return found }
        end
      end
    end
    nil
  end

  def run
    check_types(@program)
    @program.file_modules.each_value do |file_module|
      check_types(file_module)
    end
  end

  def check_types(type)
    type.types?.try &.each_value do |type|
      check_single(type)
    end
  end

  def check_single(type)
    check_fields(type)
    check_class_vars(type)
    check_types(type)
    if type.is_a?(GenericType)
      type.each_instantiated_type do |instance|
        check_fields(instance)
      end
    end
  end

  def check_fields(type)
    tape = TapeChecker.tape?(@program, type)
    if tape && !type.struct?
      fail type, nil, <<-MSG
        #{type} is marked @[OnTape] but is a class

        A tape type is a value that lives on the fiber's tape and ends with
        its Tape.use. A class instance is a heap object anything may keep a
        reference to; declare #{type} as a struct.
        MSG
    end
    return if tape
    return unless type.is_a?(InstanceVarContainer)
    return if type.is_a?(PrimitiveType) || type.is_a?(ProcInstanceType)
    type.instance_vars.each_value do |ivar|
      ivar_type = ivar.type?
      next unless ivar_type
      found = TapeChecker.tape_in(@program, ivar_type)
      next unless found
      where = type.struct? ? "a struct that is not @[OnTape], so it may itself be stored anywhere" : "a class, which lives on the heap"
      fail type, ivar, <<-MSG
        #{type}'s field `#{ivar.name} : #{ivar_type}` holds the tape type #{found}

        #{type} is #{where}, and a tape value lives only until the Tape.use
        that made it ends. Keep it in a local, a parameter or another @[OnTape]
        struct, or copy what must outlive the scope into an owned value
        (use `to_s` for Tape::String fields).
        MSG
    end
  end

  def check_class_vars(type)
    return unless type.is_a?(ClassVarContainer)
    type.class_vars?.try &.each_value do |cvar|
      cvar_type = cvar.type?
      next unless cvar_type
      found = TapeChecker.tape_in(@program, cvar_type)
      next unless found
      fail type, cvar, <<-MSG
        the class variable `#{cvar.name} : #{cvar_type}` holds the tape type #{found}

        A class variable lives as long as the program, and a tape value only
        until the Tape.use that made it ends.
        MSG
    end
  end

  private def fail(type, var, msg)
    location = var.try(&.location) || type.locations.try &.first?
    if location
      raise TypeException.new(msg, location)
    else
      raise TypeException.new(msg)
    end
  end
end
