# Type-level tape safety. Ordinary class references and @[OnTape] structs
# carry tape roots. Runtime classes retain their migration allocation ABI.
# LifetimeChecker checks the flow of roots; non-tape holders cannot contain
# them, and class finalizers cannot run after a region has been released.
class Iyi::TapeChecker
  @program : Program

  def initialize(@program)
  end

  # Runtime classes and unmarked std migrations retain iyi's allocation ABI.
  # A std class opts into checked tape storage with @[OnTape].
  # Extensions do not change the storage of the original declaration.
  def self.class_instance?(program : Program, type : Type) : Bool
    return false unless program.tape_scopes?
    type = type.remove_typedef
    type = type.base_type if type.is_a?(VirtualType)
    return false unless type.is_a?(ClassType) && !type.struct?
    declaration = type.is_a?(GenericClassInstanceType) ? type.generic_type : type
    !!declaration.locations.try(&.first?).try do |loc|
      !TapeRules.runtime?(program, loc) &&
        (!TapeRules.std?(loc) ||
          !declaration.annotation(program.tape_annotation).nil?)
    end
  end

  def self.tape?(program : Program, type : Type) : Bool
    type = type.remove_typedef
    return true if class_instance?(program, type)
    return true if TapeOwnerChecker.owner?(program, type)
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
    when ProcInstanceType
      # A proc holds what it captured, checked where it is made, not the
      # values it is called with: `Proc(Str, Nil)` holds no tape.
      return nil
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
    check_types(type)
    if type.is_a?(GenericType)
      type.each_instantiated_type do |instance|
        check_fields(instance)
      end
    end
  end

  # Views and links are fixed values; growing storage is never an element.
  private def growing_in(type : Type, visiting = Set(Type).new) : Bool
    type = type.remove_alias.remove_typedef.remove_alias
    return false unless visiting.add?(type)
    if type.is_a?(GenericClassInstanceType)
      return true if {"Ary", "Tre", "SlicePool"}.includes?(type.generic_type.name)
    end
    return true if type.to_s == "Str::Builder" ||
                   TapeOwnerChecker.owner?(@program, type)
    case type
    when UnionType
      return type.union_types.any? { |t| growing_in(t, visiting) }
    when TupleInstanceType
      return type.tuple_types.any? { |t| growing_in(t, visiting) }
    when NamedTupleInstanceType
      return type.entries.any? { |e| growing_in(e.type, visiting) }
    end
    if type.struct? && type.is_a?(InstanceVarContainer)
      return type.instance_vars.each_value.any? do |field|
        field.type?.try { |t| growing_in(t, visiting) } == true
      end
    end
    false
  end

  def check_fields(type)
    if type.is_a?(GenericClassInstanceType) &&
       {"Ary", "Tre"}.includes?(type.generic_type.name)
      type.type_vars.each_value do |var|
        # An owner element gets the owner checker's own, more exact refusal.
        if var.is_a?(Var) && (element = var.type?) &&
           !TapeOwnerChecker.owner_in(@program, element) && growing_in(element)
          fail type, nil, "#{type} cannot contain growing values in a runtime-sized collection; " \
                          "use SlicePool(T) with fixed-size elements and run handles"
        end
      end
    end
    owner = TapeOwnerChecker.owner?(@program, type)
    if owner && !type.struct?
      fail type, nil, "@[Owner] requires a struct; declare one owner per scope"
    end
    if type.is_a?(InstanceVarContainer)
      type.instance_vars.each_value do |ivar|
        if field_type = ivar.type?
          if TapeOwnerChecker.owner_in(@program, field_type)
            fail type, ivar, "cannot store an owner in a field; " \
                             "borrow it: pass the owner variable"
          end
        end
      end
    end
    tape = TapeChecker.tape?(@program, type)
    if tape && !type.struct? && !TapeChecker.class_instance?(@program, type)
      fail type, nil, <<-MSG
        #{type} is marked @[OnTape] but is a class

        A tape type is a value that lives on the fiber's tape and ends with
        its tape block. A class instance is a heap object anything may keep a
        reference to; declare #{type} as a struct.
        MSG
    end
    if TapeChecker.class_instance?(@program, type)
      type.lookup_defs("finalize").each do |a_def|
        a_def.raise "tape class instances cannot finalize; close resources explicitly; " \
                    "build retained instances on Program.tape or copy_to(owner)"
      end
    end
    if tape || type.is_a?(ClassType)
      type.lookup_defs("copy_to").each do |a_def|
        next if TapeRules.runtime?(@program, a_def.location)
        # std's own copy_to (Slice's into a target) is another method.
        next if TapeRules.std?(a_def.location)
        # Only the owner copy is generated; other arities are unrelated.
        next unless a_def.args.size == 1
        kind = tape ? "tape values" : "class instances and structs"
        a_def.raise "copy_to for #{kind} is generated deeply; " \
                    "remove this override and use .copy_to(Program.tape)"
      end
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

        #{type} is #{where}, and a tape value lives only until the tape block
        that made it ends. Keep it in a local, a parameter or another @[OnTape]
        struct, or copy what must outlive the scope into an owned value
        (`to_heap` copies a Str or Ary).
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
