# Intraprocedural view liveness. Events follow evaluation order, including
# the use of earlier operands when their enclosing call finally runs.
# Specialized call summaries converge before checking view liveness.
class Iyi::TapeShrinkChecker
  alias Guards = Array(Tuple(UInt64, Bool))
  # An index view (Array::Link) survives growth but not a shrink.
  record View, root : UInt64, born : Int32, guards : Guards = Guards.new,
    index : Bool = false
  # Roots name storage handles; views retain the storage a value borrows.
  # Holder slots carry those borrows separately so replacement can kill them.
  record Value, roots : Array(UInt64), views : Array(View),
    procs : Array(ProcLiteral) = [] of ProcLiteral,
    unknown_proc : Bool = false
  record Use, views : Array(View), node : ASTNode, guards : Guards,
    holder : String = ""
  record Shrink, roots : Array(UInt64), at : Int32, node : Call, chain : String,
    guards : Guards, growth : Bool = false, last_use : Int32? = nil
  record Summary, seeds : Array(UInt64), shrinks : Hash(UInt64, String), result : Value,
    stores : Hash(UInt64, Value) = Hash(UInt64, Value).new,
    retains : Array(UInt64) = [] of UInt64,
    grows : Hash(UInt64, String) = Hash(UInt64, String).new
  # Snapshots share variable bindings until the first write. Slot maps
  # remain independent: stores can replace or remove nested root paths.
  class Env
    getter vars : Hash(String, Value)
    getter slots : Hash(UInt64, Value)
    @shared : Bool
    delegate :[], :[]?, :keys, to: vars

    def initialize(@vars = Hash(String, Value).new,
                   @slots = Hash(UInt64, Value).new, @shared = false)
    end

    def []=(key : String, value : Value)
      if @shared
        @vars = @vars.dup
        @shared = false
      end
      @vars[key] = value
    end

    def dup
      @shared = true
      Env.new(vars, slots.dup, true)
    end

    def replace(other : Env)
      snapshot = other.dup
      @vars = snapshot.vars
      @shared = true
      @slots = snapshot.slots
    end

    def ==(other : Env)
      vars == other.vars && slots == other.slots
    end
  end

  EMPTY  = Value.new([] of UInt64, [] of View)
  SHRINK = {"clear", "truncate", "pop", "pop?", "shift", "shift?",
            "pop_n", "resize", "delete_at", "delete", "reject!", "select!"}
  VIEWS = {"finish", "span", "slice", "view", "slice_from", "[]", "[]?", "first", "first?",
           "last", "last?", "fetch", "values_at", "to_unsafe", "to_slice",
           "iterator", "each", "each_with_index", "each_byte", "each_line"}
  # String methods that answer a view of their receiver's bytes.
  TEXT_VIEWS = {"strip", "lstrip", "rstrip", "chomp", "lchop", "rchop",
                "byte_slice", "rpartition", "partition", "split", "lines",
                "as_tape", "view", "to_s", "itself", "not_nil!", "as"}
  @global_roots = Hash(UInt64, UInt64).new
  @global_ids = Set(UInt64).new
  @pooled_roots = Set(UInt64).new
  @parameter_roots = Set(UInt64).new
  @uses = [] of Use
  @shrinks = [] of Shrink

  # An owner has one named construction. Intern paths from that declaration
  # (or a call seed) so sibling fields never share an identity.
  @fields = Hash(Tuple(UInt64, String), UInt64).new
  @parents = Hash(UInt64, Tuple(UInt64, String)).new
  @next_root = 0_u64
  @returns = EMPTY
  # The returns that are not a String: a String return of a def whose
  # result is a union holding String moves down (`__iyi_scope_result`).
  @kept_returns = EMPTY
  @callback_chain = [] of String
  @active_procs = Set(UInt64).new
  @guards = Guards.new
  # Set by an If one of whose branches never falls through: the guard of
  # the branch that does, which the rest of its block runs under.
  @fallthrough = Guards.new
  @root_births = Hash(UInt64, Int32).new
  @root_types = Hash(UInt64, Type).new
  @root_scopes = Hash(UInt64, Array(UInt64)).new
  @scopes = [] of UInt64
  # SPEC 1.1, 3.2: the scopes around the walk that free their scratch
  # when they end - explicit `tape` blocks, marked defs, loop rounds and
  # blocks - innermost last, and for each fresh root the innermost one it
  # was made in. Its storage ends with that scope, so it may not be
  # stored where the destination was declared outside it.
  @tape_blocks = [] of UInt64
  @tape_kinds = Hash(UInt64, String).new
  # A marked def's result or a block's value being checked: it leaves its
  # scope through RESULT, not by a store.
  @leaving : UInt64? = nil
  # Locals bound in a loop round to data made in it: read after the loop,
  # they would view freed scratch.
  @dead = Hash(String, ASTNode).new
  @root_tapes = Hash(UInt64, UInt64).new
  @root_tape_sets = Hash(UInt64, Array(UInt64)).new
  # Per solved def, the node that wrote each stored root; while a call
  # applies a callee's stores, the callee's site for the current root.
  @store_sites = Hash(UInt64, Hash(UInt64, ASTNode)).new
  @store_site : ASTNode? = nil
  @checking = false
  @unproved = [] of Call
  @retains = [] of UInt64
  @text_roots = Set(UInt64).new
  @text_copies = Set(UInt64).new

  # Slots live in the environment, so branch and loop joins include stores.
  private def root_birth(root : UInt64) : Int32
    @root_births[root]? || @parents[root]?.try { |p| root_birth(p[0]) } || 0
  end

  private def root_scope(root : UInt64) : Array(UInt64)
    @root_scopes[root]? || @parents[root]?.try { |p| root_scope(p[0]) } || [] of UInt64
  end

  private def stored(v : Value, env : Env) : Value
    return v if v.roots.empty? || env.slots.empty?
    views = v.views.dup
    env.slots.each do |root, contents|
      if contains_root?(v.roots, root)
        views.concat(contents.views)
      end
    end
    Value.new(v.roots, views.uniq, v.procs, v.unknown_proc)
  end

  private def read_slots(v : Value, env : Env, type : Type?,
                         fields : Array(UInt64)) : Value
    result = Value.new([] of UInt64, v.views, v.procs, v.unknown_proc)
    v.roots.each do |root|
      contents = env.slots[root]?
      nested = env.slots.each_key.any? do |key|
        key != root && contains_root?([root], key)
      end
      if !fields.includes?(root)
        result = merge(result, Value.new([root], [] of View))
      elsif contents && !value_holder?(type) && !nested
        result = merge(result, contents)
      else
        result = merge(result, read_back(Value.new([root], [] of View), type, env))
      end
    end
    stored(result, env)
  end

  # A field read without a recorded store bounds a lifetime, not an
  # identity. Include every compatible owner already in scope at or above
  # that holder; parameter roots also bound caller storage.
  private def read_back(v : Value, type : Type?, env : Env) : Value
    return v unless type && @checking
    unresolved = v.roots.select { |r| @parents.has_key?(r) && !env.slots.has_key?(r) }
    return v if unresolved.empty?
    candidates = [] of UInt64
    @root_types.to_a.each do |root, candidate|
      candidate_roots(root, candidate, type).each do |candidate_root|
        if unresolved.any? { |r| root_scope(candidate_root).all? { |scope| root_scope(r).includes?(scope) } }
          candidates << candidate_root
        end
      end
    end
    born = unresolved.min_of { |r| root_birth(r) }
    return v if candidates.empty?
    Value.new((v.roots - unresolved + candidates).uniq,
      (v.views.reject { |view| unresolved.includes?(view.root) } +
       candidates.map { |r| View.new(r, born, @guards.dup) }).uniq, v.procs, v.unknown_proc)
  end

  private def candidate_roots(root : UInt64, type : Type, wanted : Type,
                              seen = Set(Type).new) : Array(UInt64)
    type = type.remove_typedef
    if wanted.is_a?(UnionType)
      return wanted.union_types.flat_map do |member|
        candidate_roots(root, type, member, seen.dup)
      end.uniq
    end
    return [] of UInt64 unless seen.add?(type)
    name = type_name(type)
    target = type_name(wanted.remove_typedef)
    compatible = name == target ||
                 ({"String", "String::Span"}.includes?(target) &&
                  {"String::Builder", "Array(UInt8)"}.includes?(name))
    result = compatible ? [root] : [] of UInt64
    # A reference field does not own the bytes it views. By-value nesting
    # does: inspect it even when its getter has not yet been called.
    if type.struct? && type.is_a?(InstanceVarContainer) &&
       !storage_type?(type) && !{"String", "String::Span"}.includes?(name)
      type.instance_vars.each do |field, var|
        if field_type = var.type?
          next if {"String", "String::Span"}.includes?(type_name(field_type))
          next if field_type.is_a?(PointerInstanceType)
          result.concat(candidate_roots(field_root(root, field), field_type,
            wanted, seen.dup))
        end
      end
    end
    result
  end

  private def relative_path(root : UInt64, base : UInt64) : Array(String)?
    return [] of String if root == base
    if parent = @parents[root]?
      relative_path(parent[0], base).try { |path| path + [parent[1]] }
    end
  end

  private def aliases(root : UInt64, env : Env,
                      seen = Set(UInt64).new) : Array(UInt64)
    return [] of UInt64 unless seen.add?(root)
    result = [root]
    if parent = @parents[root]?
      aliases(parent[0], env, seen).each do |base|
        result << field_root(base, parent[1])
      end
    end
    env.slots[root]?.try &.roots.each do |source|
      # A constructor's receiver is rebased into the field, not shared
      # by every sibling. Borrowed storage has a separate declaration.
      next if contains_root?([source], root)
      result.concat(aliases(source, env, seen))
    end
    result.uniq
  end

  private def store(roots : Array(UInt64), v : Value, env : Env,
                    node : ASTNode, replace = true)
    roots = roots.flat_map do |root|
      if parent = @parents[root]?
        aliases(parent[0], env).map { |base| field_root(base, parent[1]) }
      else
        [root]
      end
    end.uniq
    # Where a def's store is written, for the refusal at its callers: the
    # store itself, or the deeper one a call here carries.
    if solving = @solving
      sites = @store_sites[solving] ||= Hash(UInt64, ASTNode).new
      roots.each { |root| sites[root] ||= @store_site || node }
    end
    # Copy a by-value holder's slots, rather than baking its aggregate
    # roots into the parent. This lets an emptied nested field forget its
    # roots without changing a separate copy of the holder.
    copies = Hash(Array(String), Value).new
    carried = [] of View
    copied = [] of UInt64
    holders = v.roots.select { |source|
      value_holder?(@root_types[source]?)
    }.to_set
    unless holders.empty?
      # Walk each slot's bounded parent path once. Scanning every slot
      # for every possible source made broad loop joins quadratic.
      env.slots.each do |root, contents|
        ancestor = root
        path = [] of String
        while parent = @parents[ancestor]?
          path.unshift(parent[1])
          ancestor = parent[0]
          next unless holders.includes?(ancestor)
          copies[path.dup] = merge(copies[path]? || EMPTY, contents)
          carried.concat(contents.views)
          copied << ancestor
        end
      end
    end
    if @checking && !@text_only
      complete = stored(v, env)
      roots.each { |root| check_store(root, complete, node) }
    end
    v = Value.new(v.roots - copied,
      (v.views - carried).uniq, v.procs, v.unknown_proc)
    # An array/builder handle aliases storage; it is not itself a live
    # element view. Otherwise consuming that handle to clear it would
    # falsely keep a view alive across its own clear.
    borrowed = v.roots.reject do |root|
      type = @root_types[root]?
      value_holder?(type) || storage_type?(type)
    end
    v = Value.new(v.roots, (v.views + borrowed.map { |r| view(r) }).uniq, v.procs, v.unknown_proc)
    roots.each do |root|
      # A folded slot represents several concrete fields. Replacing one
      # must preserve the borrows held by the others.
      strong = replace && roots.size == 1 && !@folded_roots.includes?(root)
      if strong
        env.slots.reject! do |key, _|
          contains_root?([root], key)
        end
      end
      env.slots[root] = strong ? v : merge(env.slots[root]? || EMPTY, v)
      copies.each do |path, contents|
        destination = root
        path.each { |name| destination = field_root(destination, name) }
        env.slots[destination] = strong && !@folded_roots.includes?(destination) ? contents : merge(env.slots[destination]? || EMPTY, contents)
      end
    end
  end

  private def value_holder_uncached(type : Type?) : Bool
    return false unless type
    type = type.remove_typedef
    if type.is_a?(UnionType)
      members = type.union_types.select { |t| TapeChecker.tape_in(@program, t) }
      return !members.empty? && members.all? { |t| value_holder?(t) }
    end
    type.struct? && TapeChecker.tape?(@program, type) &&
      !TapeOwnerChecker.owner?(@program, type) && !storage_type?(type) &&
      !{"String", "String::Span"}.includes?(type_name(type))
  end

  private def source_roots(v : Value) : Array(UInt64)
    # A holder a one-call def handed on holds what the call made, which
    # no slot view names: it is a source itself.
    v.roots.reject { |r| value_holder?(@root_types[r]?) && !@handed.includes?(r) } + v.views.map(&.root)
  end

  private def source_scope(root : UInt64) : Array(UInt64)
    declaration = root
    while parent = @parents[declaration]?
      declaration = parent[0]
    end
    type = @root_types[declaration]?
    # A copied tape handle's header is not the owner of its bytes. Only
    # named owners introduce a shorter lifetime than the caller's tape;
    # a holder's recorded roots carry any such owner through the copy.
    type && TapeOwnerChecker.owner?(@program, type) ? root_scope(root) : [] of UInt64
  end

  private def check_store(root : UInt64, v : Value, node : ASTNode)
    if @checking && !@text_only
      destinations = root_scope(root)
      source_roots(v).each do |source|
        # A struct is stored by value: its bytes are copied, and what its
        # fields hold is checked through the value's views.
        next if struct_value?(source) && !@handed.includes?(source)
        scope = source_scope(source)
        unless scope.all? { |part| destinations.includes?(part) }
          node.raise "cannot store a view beyond its owner scope; " \
                     "copy it with copy_to(owner) before storing it"
        end
        if (block = tape_of(source)) && !leaving?(source) && outside?(root, block)
          STDERR.puts "DBG store #{root_name(source)} #{@root_types[source]?} sv=#{struct_value?(source)} dst=#{root_name(root)} at #{node.location}" if ENV["RIS_DBG"]?
          message = scope_message(block)
          # The store is in a method this call reaches (a handler's
          # `call`): point at that line, and name the call that reaches it.
          site = @store_site
          if site && site.location && !site.same?(node) &&
             (call_at = node.location)
            site.raise "#{message}\nThis store runs inside the tape block " \
                       "of the call at " \
                       "#{call_at.original_filename.try { |f| File.expand_path(f) }}:" \
                       "#{call_at.line_number}"
          end
          refuse(node, message)
        end
      end
    end
  end

  # The innermost explicit `tape` block *root* was made in, if any.
  private def tape_of(root : UInt64) : UInt64?
    declaration = root
    while true
      if block = @root_tapes[declaration]?
        return block
      end
      parent = @parents[declaration]?
      return nil unless parent
      declaration = parent[0]
    end
  end

  private def copying_text?(node : ASTNode) : Bool
    return false unless node.is_a?(Call) &&
      {"build", "interpolate", "interpolation"}.includes?(node.name)
    return false unless node.obj.try(&.type?).try { |t|
      t.metaclass? && t.instance_type.to_s == "String"
    }
    targets = @graph.targets(node)
    !!targets && !targets.empty? &&
      targets.all? { |d| TapeRules.runtime?(@program, d.location) }
  end

  # Text built inside a `tape` block - an interpolation, or a call that
  # allocates and answers a String viewing none of its inputs - is that
  # block's storage, as an allocated Array is.
  private def tape_text(node : ASTNode, result : Value) : Value
    return result if @tape_blocks.empty? || !@checking
    return result unless node.type?.try { |t| type_name(t.remove_typedef) } == "String"
    # A call that allocates and answers text made its bytes, though its
    # summary may show only the inputs it read (interpolation, inspect):
    # unless it is known to answer a view, the text is fresh too.
    # A copy is on its owner (copy_to(Program.tape)), not this block.
    return result if node.is_a?(Call) && {"copy_to", "to_heap"}.includes?(node.name)
    # Growing text answers the text grown, in its own reservation.
    return result if node.is_a?(Call) && node.obj.try(&.type?.try(&.to_s)) == "RisTextGrowth"
    # These runtime constructors copy every input byte. Their output is
    # independent even when the inputs view a local owner's fields.
    copied_text = copying_text?(node)
    result = EMPTY if copied_text
    viewing = !(result.roots.empty? && result.views.empty?)
    return result if viewing && node.is_a?(Call) &&
                     (VIEWS.includes?(node.name) || TEXT_VIEWS.includes?(node.name))
    return result if viewing && !node.is_a?(Call)
    # A view of a builder's or an Array's storage is what it says.
    if viewing && (result.roots + result.views.map(&.root)).all? { |r|
         storage_type?(root_type(r)) && type_name(root_type(r).not_nil!.remove_typedef) != "String"
       }
      return result
    end
    made = copied_text || node.is_a?(StringInterpolation) ||
           (node.is_a?(Call) && !node.expanded && @graph.allocates?(node))
    return result unless made
    @root_scopes[node.object_id] = @scopes.dup
    @root_types[node.object_id] = node.type
    @root_births[node.object_id] = @uses.size
    note_fresh(node.object_id)
    Value.new([node.object_id], result.views, result.procs, result.unknown_proc)
  end

  # A scope refusal (SPEC 3.6). With RIS_SCOPE_ERRORS=all every one is
  # listed on standard error, one line each, and the first is raised when
  # the walk ends: a migration sees them all at once, and still fails.
  @first_refusal : {ASTNode, String}? = nil

  def refuse(node : ASTNode, message : String, holds : String = "") : Nil
    node.raise message unless ENV["RIS_SCOPE_ERRORS"]? == "all"
    loc = node.location
    detail = holds.empty? ? "" : " [#{holds}]"
    STDERR.puts "refused #{loc.try(&.original_filename)}:#{loc.try(&.line_number)}: #{message.lines.first}#{detail}"
    @first_refusal ||= {node, message}
  end

  # What a store of data made in *block* says, by the kind of scope.
  private def scope_message(block : UInt64) : String
    kind = @tape_kinds[block]? || "tape block"
    if kind == "tape block"
      "cannot store data made in this tape block where it " \
      "outlives the block (SPEC 3.2): its storage ends " \
      "with the block.\nCopy it with .copy_to(owner) onto the " \
      "destination's owner, or build it on the destination " \
      "(write into its String::Builder)"
    else
      "cannot store data made in this #{kind} where it outlives the " \
      "#{kind} (SPEC 1.1, 3.6): every def, loop round and block frees " \
      "its scratch when it ends.\nCopy it with .copy_to(owner) onto the " \
      "destination's owner, write it into a parameter (a " \
      "String::Builder or Array the caller owns), clear and refill a " \
      "value made before, or read the value before the loop"
    end
  end

  # Storage a constructor or an unmarked call makes, put into *roots*:
  # it is on the innermost scope's scratch, so a destination from outside
  # that scope would keep a view of it past its end (SPEC 3.6).
  private def refuse_fresh_store(roots : Array(UInt64), node : ASTNode) : Nil
    return unless @checking && !@text_only
    return unless block = @tape_blocks.last?
    return unless roots.any? { |r| outside?(r, block) }
    refuse(node, scope_message(block))
  end

  private def note_fresh(root : UInt64) : Nil
    if block = @tape_blocks.last?
      @root_tapes[root] = block
      @root_tape_sets[root] = @tape_blocks.dup
    end
  end

  # Whether *root* is known to live outside the tape block *block*: a
  # binding or allocation from before it, a parameter, `self` or program
  # data. A callee's own new holder, which reaches here without any of
  # these, is made during the call and so inside the block.
  private def outside?(root : UInt64, block : UInt64) : Bool
    return false if within?(root, block)
    declaration = root
    while true
      return true if @root_scopes.has_key?(declaration) ||
                     @parameter_roots.includes?(declaration) ||
                     @global_ids.includes?(declaration)
      parent = @parents[declaration]?
      return false unless parent
      declaration = parent[0]
    end
  end

  # Whether *root* was declared or made inside the tape block *block*.
  private def within?(root : UInt64, block : UInt64) : Bool
    return true if root_scope(root).includes?(block)
    declaration = root
    while true
      if blocks = @root_tape_sets[declaration]?
        return blocks.includes?(block)
      end
      parent = @parents[declaration]?
      return false unless parent
      declaration = parent[0]
    end
  end

  private def bind(target : Var, v : Value, env : Env, node : ASTNode)
    @dead.delete(target.name)
    binding = "#binding:#{target.name}"
    declaration = env[binding]? || begin
      @root_scopes[target.object_id] = @scopes.dup
      env[binding] = Value.new([target.object_id], [] of View)
    end
    if @checking && !@text_only && reference?(target) &&
       !target.type?.try(&.remove_typedef.is_a?(PointerInstanceType))
      complete = stored(v, env)
      declaration.roots.each { |root| check_store(root, complete, node) }
    end
    env[target.name] = v
  end

  private def translated(v : Value, summary : Summary,
                         inputs : Array(Value), allocation : UInt64? = nil) : Value
    roots = v.roots.flat_map { |r| translate(r, summary, inputs, allocation) }.uniq
    views = v.views.flat_map do |v|
      translate(v.root, summary, inputs, allocation).map { |r| view(r).copy_with(index: v.index) }
    end
    Value.new(roots, views)
  end

  private def view(root : UInt64) : View
    View.new(root, @uses.size, @guards.dup)
  end

  private def shrink(roots : Array(UInt64), node : Call, chain : String,
                     growth = false)
    return if @text_only && !chain.includes?("text reset")
    @shrinks << Shrink.new(roots, @uses.size, node, chain, @guards.dup,
      growth)
    # What is made after it - a callee's refill of what it cleared - is
    # born after it.
    @uses << Use.new([] of View, node, @guards.dup)
  end

  # Reset invalidates the bytes behind the companion, not the object
  # holding it. The binding being replaced is the one permitted holder.
  private def text_root?(root : UInt64) : Bool
    return true if @text_roots.includes?(root)
    if parent = @parents[root]?
      parent[1].starts_with?("@__ris_text_") || text_root?(parent[0])
    else
      false
    end
  end

  private def text_reset(roots : Array(UInt64), node : Call, env : Env,
                         cause : String)
    shrink(roots, node, cause)
    env.vars.each do |name, v|
      next if name == "self" || name.starts_with?("__temp_") ||
              name.starts_with?("#") || name.starts_with?("@")
      use(Value.new([] of UInt64,
        v.views.select { |view| contains_root?(roots, view.root) }),
        node, name)
    end
    env.slots.each do |slot, v|
      # If-expression scope records are evaluation temporaries, not
      # retained holders. Named allocations and field paths have types.
      next unless @parents.has_key?(slot) || @root_types.has_key?(slot)
      own = roots.any? do |root|
        next true if contains_root?([root], slot)
        parent = @parents[root]?
        field = @parents[slot]?
        parent && field && parent[0] == field[0] &&
          parent[1] == "@__ris_text_#{field[1].lchop('@')}"
      end
      helper_input = if parent = @parents[slot]?
                       node.name == "__ris_text_reset_#{parent[1].lchop('@')}"
                     else
                       false
                     end
      unless own && !helper_input
        use(Value.new([] of UInt64,
          v.views.select { |view| contains_root?(roots, view.root) }),
          node, root_name(slot))
      end
    end
    use(Value.new([] of UInt64,
      @returns.views.select { |view| contains_root?(roots, view.root) }),
      node, "returned value")
    # A view made by the reset is born after the invalidation.
    use(EMPTY, node)
  end

  # A branch that ends in `return` leaves the def: nothing used after it
  # in the def's text runs after its shrinks (a caller sees them through
  # the summary). Uses inside the branch still count.
  private def leave_branch(branch : ASTNode, from : Int32) : Nil
    return unless @checking
    last = branch.is_a?(Expressions) ? branch.expressions.last? : branch
    return unless last.is_a?(Return)
    (from...@shrinks.size).each do |i|
      shrink = @shrinks[i]
      @shrinks[i] = shrink.copy_with(last_use: shrink.last_use || @uses.size)
    end
  end

  private def compatible?(a : Guards, b : Guards) : Bool
    !a.any? { |x| b.any? { |y| x[0] == y[0] && x[1] != y[1] } }
  end

  private def chain(name : String) : String
    (@callback_chain + [name]).join(" -> ")
  end

  private def fresh : UInt64
    @next_root += 1
  end

  # Field paths deeper than this fold onto their ancestor at this depth.
  FIELD_DEPTH = 6

  @folded_roots = Set(UInt64).new

  private def field_root(root : UInt64, name : String) : UInt64
    # Fold repeated fields onto their ancestor. Recursive calls can walk
    # arbitrarily deep containers; conflating these paths keeps the effect
    # domain finite and conservatively aliases their storage. A deep path
    # of distinct names (@frames.@conn.@state.@socket...) folds too, or
    # each level makes new roots and a loop's state grows past use.
    ancestor = root
    depth = 0
    base = nil
    while parent = @parents[ancestor]?
      # A same-named field is the same one only on the same owner type: a
      # socket's @state inside a connection's @state is another field.
      # Unknown types fold, which conflates and so stays sound; depth bounds
      # the rest.
      if parent[1] == name && name != "[]" &&
         same_owner?(parent[0], base ||= field_type(root))
        @folded_roots << ancestor
        return ancestor
      end
      ancestor = parent[0]
      depth += 1
    end
    if depth >= FIELD_DEPTH
      @folded_roots << root
      return root
    end
    @fields[{root, name}] ||= begin
      id = fresh
      @parents[id] = {root, name}
      id
    end
  end

  # Whether *base*'s type, when known, has the instance variable *name*.
  # Unknown types and synthetic names fit, keeping the effect.
  private def field_fits?(base : UInt64, name : String) : Bool
    return true unless name.starts_with?('@') && !name.starts_with?("@__")
    type = field_type(base)
    return true unless type
    type_fits?(type.remove_typedef, name)
  end

  # root_type, seeing through pointers and unions on the way down.
  private def same_owner?(other : UInt64, base : Type?) : Bool
    type = field_type(other)
    return true unless base && type
    type.remove_typedef == base.remove_typedef
  end

  private def field_type(root : UInt64) : Type?
    if type = @root_types[root]?
      return type
    end
    parent = @parents[root]?
    return nil unless parent
    owners = [field_type(parent[0]).try(&.remove_typedef)].compact
    found = [] of Type
    while owner = owners.pop?
      case owner
      when UnionType
        owner.union_types.each { |member| owners << member.remove_typedef }
      when PointerInstanceType
        owners << owner.element_type.remove_typedef
      when InstanceVarContainer
        owner.instance_vars[parent[1]]?.try(&.type?).try { |t| found << t }
      end
    end
    found.size == 1 ? found[0] : nil
  end

  private def type_fits?(type : Type, name : String) : Bool
    case type
    when UnionType
      type.union_types.any? { |member| type_fits?(member.remove_typedef, name) }
    when PointerInstanceType
      type_fits?(type.element_type.remove_typedef, name)
    when NilType
      false
    when InstanceVarContainer
      type.instance_vars.has_key?(name)
    else
      true
    end
  end

  private def seed_env(target : Def, seeds : Array(UInt64)) : Env
    env = Env.new
    env["self"] = Value.new([seeds[0]], [] of View)
    if owner = target.owner?
      @root_types[seeds[0]] = owner
    end

    target.args.each_with_index do |arg, i|
      @root_types[seeds[i + 1]] = arg.type if arg.type?
      env[arg.name] = reference?(arg) ? Value.new([seeds[i + 1]], [] of View) : EMPTY
    end
    env
  end

  private def translate(root : UInt64, summary : Summary,
                        inputs : Array(Value), allocation : UInt64? = nil) : Array(UInt64)
    if i = summary.seeds.index(root)
      input = inputs[i]? || EMPTY
      input.roots.empty? ? input.views.map(&.root) : input.roots
    elsif parent = @parents[root]?
      bases = translate(parent[0], summary, inputs, allocation)
      # A view taken as a base (a String an argument borrows) has none of
      # the callee's fields: mapping them there would invent paths such as
      # String.@stream.@tls, which then alias unrelated storage.
      bases = bases.select { |base| field_fits?(base, parent[1]) }
      bases.map do |base|
        mapped = field_root(base, parent[1])
        if @text_only && (type = @root_types[root]?)
          @root_types[mapped] ||= type
        end
        mapped
      end
    elsif @global_ids.includes?(root)
      [root]
    elsif allocation && summary.result.roots.includes?(root)
      [allocation]
    elsif @text_only && allocation && @text_copies.includes?(root)
      # A fresh copy stored inside a returned holder is independent too.
      # Keep its identity instead of losing it at the call boundary and
      # broadening the holder's next field read to every in-scope String.
      copied = field_root(allocation, "#text_copy")
      if type = @root_types[root]?
        @root_types[copied] = type
      end
      [copied]
    else
      [] of UInt64
    end
  end

  # Do not solve a second provenance lattice for programs with no
  # executable growing-String reset. Definitions alone do not count.
  def self.text_resets?(graph : TapeCallGraph, root : ASTNode) : Bool
    scan = TextResetScan.new
    root.accept(scan)
    graph.defs.each_value { |target| target.body.accept(scan) }
    graph.program.const_initializers.each { |i| i.value.accept(scan) }
    graph.program.class_var_initializers.each { |i| i.node.accept(scan) }
    scan.found?
  end

  class TextResetScan < Visitor
    getter? found = false

    def visit(node : Call)
      if node.name == "__ris_text_reset" &&
         node.obj.try(&.type?.try(&.to_s)) == "RisTextGrowth" &&
         TapeChecker.possible_string?(node.type?)
        @found = true
      end
      node.expanded.try &.accept(self)
      !@found
    end

    def visit(node : Def | Macro)
      false
    end

    def visit(node : ASTNode)
      !@found
    end
  end

  @reset_summaries = Hash(UInt64, Summary).new

  def initialize(@program : Program, @graph : TapeCallGraph,
                 @text_only : Bool = false)
  end

  private def summary(target : Def) : Summary?
    @text_only ? @reset_summaries[target.object_id]? :
      @graph.effects[target.object_id]?.try(&.shrink)
  end

  private def save_summary(target : Def, value : Summary)
    if @text_only
      @reset_summaries[target.object_id] = value
    else
      @graph.effects[target.object_id].shrink = value
    end
  end

  @solving : UInt64?
  @owned_defs : Hash(Type, Array(Def))? = nil

  WHOLE = ["*"]

  # What an unknown proc can do to a value it is handed: only what that
  # value's own methods do, or the methods of what they hand out (a
  # getter's field, a returned value). It cannot touch a private field
  # but through a method, so a method's summary says which fields it
  # shrinks (*retain* false) or retains (*retain* true). Nil: nothing;
  # WHOLE: the whole value; else those fields. Storage (Array, Hash,
  # Builder, RisTree), pointers, procs, modules, abstract and virtual
  # types, runtime methods and anything unknown are WHOLE. A summary read
  # while solving makes this def solved again when it changes.
  private def handed_effect(type : Type?, retain : Bool,
                            seen = Set(Type).new) : Array(String)?
    return WHOLE unless type
    type = type.remove_typedef
    if type.is_a?(UnionType)
      names = [] of String
      type.union_types.each do |member|
        found = handed_effect(member, retain, seen)
        return WHOLE if found == WHOLE
        names.concat(found) if found
      end
      return names.empty? ? nil : names.uniq
    end
    return nil if type.is_a?(NilType) || type.is_a?(BoolType) ||
                  type.is_a?(CharType) || type.is_a?(IntegerType) ||
                  type.is_a?(FloatType) || type.is_a?(SymbolType) ||
                  type.is_a?(EnumType)
    name = type_name(type)
    # A String is immutable, but a proc may keep it.
    return (retain ? WHOLE : nil) if name == "String"
    return WHOLE if storage_type?(type) || name.starts_with?("Pointer(") ||
                    name.starts_with?("Slice(") || name.includes?("View(") ||
                    name == "String::Span" || name.starts_with?("Array::Link(")
    return WHOLE if type.is_a?(ProcInstanceType) || type.is_a?(VirtualType) ||
                    type.is_a?(VirtualMetaclassType) || type.abstract? ||
                    type.module? || !type.is_a?(InstanceVarContainer)
    # A type with no fields holds no storage to shrink or keep.
    return nil if type.instance_vars.empty? && !type.is_a?(GenericClassInstanceType)
    # A type met again is being decided further up.
    return nil unless seen.add?(type)
    names = [] of String
    # Object, Reference, Value and Struct give every type the same generic
    # methods (identity, hashing, inspection, dup): none frees or keeps
    # storage.
    owners = ([type] + type.ancestors).reject do |owner|
      {"Object", "Reference", "Value", "Struct"}.includes?(type_name(owner))
    end
    owners.each do |owner|
      # A runtime body is opaque: no summary says what it does.
      owner.defs.try &.each_value do |items|
        return WHOLE if items.any? { |item| TapeRules.runtime?(@program, item.def.location) }
      end
      owned_defs[owner]?.try &.each do |method|
        # A constructor runs on a new value, never on one handed over.
        next if method.name == "initialize"
        if caller = @solving
          (@summary_callers[method.object_id] ||= Set(UInt64).new) << caller
        end
        found = summary(method)
        return WHOLE unless found
        roots = retain ? found.retains : found.shrinks.keys + found.grows.keys
        roots.each do |root|
          # Another parameter's effect belongs to that value.
          path = relative_path(root, found.seeds[0])
          next unless path
          return WHOLE if path.empty?
          names << path[0]
        end
        # What a method hands out of the value (its result views a field)
        # is open to the proc as well.
        if handed_effect(method.type?, retain, seen)
          (found.result.roots + found.result.views.map(&.root)).each do |root|
            path = relative_path(root, found.seeds[0])
            names << path[0] if path && !path.empty?
          end
        end
      end
    end
    names.empty? ? nil : names.uniq
  end

  # What a proc's *index*th parameter is declared as; nil when unknown.
  private def proc_argument_type(target : Def, index : Int32) : Type?
    target.args[index]?.try(&.type?) ||
      target.owner?.as?(ProcInstanceType).try(&.arg_types[index]?)
  end

  # A handed object's field, bounded by depth as `field_root` is but not
  # folded onto an ancestor of the same name: a socket's `@state` is not
  # the connection's.
  private def handed_field(root : UInt64, name : String) : UInt64
    depth = 0
    ancestor = root
    while parent = @parents[ancestor]?
      ancestor = parent[0]
      depth += 1
    end
    return root if depth >= FIELD_DEPTH
    @fields[{root, name}] ||= begin
      id = fresh
      @parents[id] = {root, name}
      id
    end
  end

  private def owned_defs : Hash(Type, Array(Def))
    @owned_defs ||= begin
      map = Hash(Type, Array(Def)).new
      @graph.defs.each_value do |method|
        owner = method.owner?
        (map[owner] ||= [] of Def) << method if owner
      end
      map
    end
  end
  @summary_callers = Hash(UInt64, Set(UInt64)).new

  # Calls in lexical callbacks execute in the enclosing environment too.
  class Dependencies < Visitor
    def initialize(@graph : TapeCallGraph, @caller : UInt64,
                   @callers : Hash(UInt64, Set(UInt64)))
    end

    def visit(node : Call)
      if expanded = node.expanded
        expanded.accept self
        return false
      end
      @graph.targets(node).try &.each do |target|
        (@callers[target.object_id] ||= Set(UInt64).new) << @caller
      end
      true
    end

    def visit(node : ProcLiteral)
      node.def.body.accept self
      false
    end

    def visit(node : Def)
      false
    end

    def visit(node : ASTNode)
      true
    end
  end

  def solve
    @graph.defs.each_value do |target|
      seeds = Array(UInt64).new(target.args.size + 1) { fresh }
      @parameter_roots.concat(seeds)
      save_summary(target, Summary.new(seeds, Hash(UInt64, String).new, EMPTY))
    end
    callers = Hash(UInt64, Set(UInt64)).new
    @graph.defs.each_value do |target|
      target.body.accept Dependencies.new(@graph, target.object_id, callers)
    end
    # Keep definition order so the first diagnostic chain stays stable.
    # Later callers run in this sweep; earlier callers run in the next.
    dirty = @graph.defs.keys.to_set
    loop do
      changed = false
      @graph.defs.each_value do |target|
        next unless dirty.delete(target.object_id)
        @root_sets.clear
        @solving = target.object_id
        old = summary(target).not_nil!
        @uses.clear
        @shrinks.clear
        @returns = EMPTY
        @kept_returns = EMPTY
        @retains.clear
        env = seed_env(target, old.seeds)
        result = merge(value(target.body, env), @returns)
        effects = old.shrinks.dup
        grows = old.grows.dup
        @shrinks.each do |effect|
          destination = effect.growth ? grows : effects
          effect.roots.each { |root| destination[root] ||= effect.chain }
        end
        # Local allocations cannot be exported as parameter effects.
        effects.reject! { |root, _| translate(root, old, old.seeds.map { |r| Value.new([r], [] of View) }).empty? }
        grows.reject! do |root, _|
          translate(root, old, old.seeds.map do |r|
            Value.new([r], [] of View)
          end).empty?
        end
        result = Value.new(result.roots, result.views.map { |v| View.new(v.root, 0, index: v.index) })
        stores = old.stores.dup
        env.slots.each do |root, contents|
          next if translate(root, old, old.seeds.map { |r| Value.new([r], [] of View) }).empty? && !contains_root?(result.roots, root)
          canonical = Value.new(contents.roots, contents.views.map { |v| View.new(v.root, 0, index: v.index) })
          stores[root] = canonical
        end
        updated = Summary.new(old.seeds, effects, merge(old.result, result), stores,
          (old.retains + @retains).uniq, grows)
        if updated != old
          changed = true
          callers[target.object_id]?.try { |ids| dirty.concat(ids) }
          @summary_callers[target.object_id]?.try { |ids| dirty.concat(ids) }
        end
        save_summary(target, updated)
      end
      break unless changed
    end
    @solving = nil
    return if @text_only
    # Project root paths conservatively onto their parameter. The wire
    # contract may overestimate a field effect, but never loses one.
    @graph.defs.each_value do |target|
      next if target.is_a?(External)
      summary = summary(target).not_nil!
      effect = @graph.effects[target.object_id]
      flags = summary.seeds.map do |seed|
        bits = 0
        bits |= TapeCallGraph::Contract::SHRINK if (summary.shrinks.keys + summary.grows.keys).any? { |r| relative_path(r, seed) }
        result_roots = summary.result.roots + summary.result.views.map(&.root)
        # A returned holder may carry the dependency in a nested slot.
        summary.stores.each do |root, contents|
          if contains_root?(summary.result.roots, root)
            result_roots.concat(contents.roots + contents.views.map(&.root))
          end
        end
        bits |= TapeCallGraph::Contract::RESULT if result_roots.any? { |r| relative_path(r, seed) }
        # Keep a receiver store distinct from an unbounded escape. The
        # consumer can check the receiver's scope even without the body.
        retained = summary.retains.any? { |r| relative_path(r, seed) }
        summary.stores.each do |destination, contents|
          next unless source_roots(contents).any? { |r| relative_path(r, seed) }
          if relative_path(destination, summary.seeds[0])
            bits |= TapeCallGraph::Contract::STORE_SELF
          else
            retained = true
          end
        end
        bits |= TapeCallGraph::Contract::RETAIN if retained
        bits |= TapeCallGraph::Contract::SUSPEND if effect.suspension
        bits
      end
      origin = target.iyi_origin || target
      # Default/named/splat expansions can reorder or omit arguments. A
      # signature is in the written order, never the expansion's order.
      if !origin.same?(target)
        flags = [flags[0]] + origin.args.map do |arg|
          index = target.args.index { |actual| actual.name == arg.name }
          index ? flags[index + 1] : TapeCallGraph::Contract::ALL
        end
      end
      checked = TapeCallGraph::Contract.new(flags, effect.allocation, effect.suspension)
      if old = origin.ris_call_contract
        checked = checked.join(TapeCallGraph::Contract.decode(old))
      end
      origin.ris_call_contract = checked.encode
    end
  end

  def run(node : ASTNode)
    @graph.defs.each_value do |target|
      # The generated helper consumes the field after its rebinding.
      # Check its effect and input at that call site, where the new
      # field value's provenance is available.
      next if @text_only && target.name.starts_with?("__ris_text_reset_") && target.args.empty?
      check(target.body, seed_env(target, summary(target).not_nil!.seeds), target) unless TapeRules.unsafe?(@program, target)
    end
    check(node)
    @program.const_initializers.each { |i| check(i.value) }
    @program.class_var_initializers.each { |i| check(i.node) }
    if first = @first_refusal
      first[0].raise first[1]
    end
  end

  private def root_name(root : UInt64) : String
    if parent = @parents[root]?
      "#{root_name(parent[0])}.#{parent[1]}"
    else
      @root_types[root]?.try(&.to_s) || "tape"
    end
  end

  private def root_type(root : UInt64) : Type?
    if type = @root_types[root]?
      return type
    end
    if parent = @parents[root]?
      type = one_class(root_type(parent[0]))
      if type.is_a?(InstanceVarContainer)
        return type.instance_vars[parent[1]]?.try(&.type?)
      end
    end
    nil
  end

  # Root arrays are immutable values. Index large ones by identity, keeping
  # the array alive alongside its index so an identity cannot be reused.
  # Clear the cache at definition boundaries to bound its lifetime.
  @root_sets = Hash(UInt64, Tuple(Array(UInt64), Set(UInt64))).new

  private def contains_root?(roots : Array(UInt64), root : UInt64) : Bool
    if roots.size > 8
      indexed = @root_sets[roots.object_id] ||= {roots, roots.to_set}
      loop do
        return true if indexed[1].includes?(root)
        parent = @parents[root]?
        return false unless parent
        root = parent[0]
      end
    else
      loop do
        return true if roots.includes?(root)
        parent = @parents[root]?
        return false unless parent
        root = parent[0]
      end
    end
  end

  private def check(body : ASTNode, env = Env.new, owner : Def? = nil)
    @root_sets.clear
    @uses.clear
    @shrinks.clear
    @returns = EMPTY
    @kept_returns = EMPTY
    @checking = true
    @unproved.clear
    @scopes.clear
    # Constructors build their locals and fields in the caller's scope.
    @scopes << owner.object_id if owner && !TapeScopeChecker.constructor?(owner)
    @root_scopes.clear
    @root_births.clear
    @tape_blocks.clear
    @root_tapes.clear
    @root_tape_sets.clear
    @dead.clear
    @leaving = nil
    # A marked def frees its scratch when it ends (SPEC 1.1).
    marked = owner && !TapeScopeChecker.constructor?(owner) &&
             !TapeScopeChecker.parts(owner.body).nil?
    if owner && marked
      @tape_blocks << owner.object_id
      @tape_kinds[owner.object_id] = "def"
    end
    live = (env.vars.values + env.slots.values).flat_map(&.roots).to_set
    @root_types.select! { |root, _| live.includes?(root) }
    if @text_only && owner && (type = owner.owner?).is_a?(InstanceVarContainer)
      # Checking a method starts with existing field contents. Seed the
      # unknown old borrow on both branch paths; a definite store kills
      # it, while a store on only one path cannot erase the other path.
      @program.ris_growing_field_names.each do |name|
        next unless TapeChecker.possible_string?(type.instance_vars[name]?.try(&.type?))
        (env["self"]? || EMPTY).roots.each do |root|
          slot = field_root(root, name)
          companion = field_root(root, "@__ris_text_#{name.lchop('@')}")
          env.slots[slot] = Value.new([] of UInt64, [View.new(companion, 0)])
        end
      end
    end
    last = value(body, env)
    result = merge(last, @returns)
    if owner && !TapeScopeChecker.constructor?(owner)
      if marked
        # A String that ends a def whose result is a union with String
        # moves down; the rest is checked.
        leaving = result
        if union_with_text?(owner.type?) || owner.type?.try { |t| one_text_struct?(t.remove_typedef) }
          leaving = merge(moved_text?(body) || ends_in_return?(body) ? EMPTY : last, @kept_returns)
        end
        check_leaving(owner.object_id, leaving, env, owner.type?, owner)
        @leaving = owner.object_id
      end
      boundary = fresh
      @root_scopes[boundary] = [] of UInt64
      check_store(boundary, stored(result, env), body)
      @leaving = nil
    end
    @checking = false
    @shrinks.each do |shrink|
      if shrink.growth
        next unless shrink.roots.any? do |root|
          @pooled_roots.includes?(root) ||
            (parameter_root?(root) && !class_field_root?(root) &&
             possible_array?(@text_only ? root_type(root) : @root_types[root]?))
        end
      end
      @uses.each_with_index do |use, i|
        next if i < shrink.at
        next if (last = shrink.last_use) && i >= last
        next unless compatible?(shrink.guards, use.guards)
        if live = use.views.find { |view| !(shrink.growth && view.index) && view.born <= shrink.at && compatible?(view.guards, shrink.guards) && contains_root?(shrink.roots, view.root) }
          action = shrink.growth ? "grow a pool run" : "shrink tape storage"
          shrink.node.raise "cannot #{action} with a live view " \
                            "of #{root_name(live.root)} while shrinking " \
                            "#{shrink.roots.map { |r| root_name(r) }.join(", ")}, " \
                            "used at #{use.node.location}#{use.holder.empty? ? "" : " " + use.holder} via #{shrink.chain}: copy the view first " \
                            "with copy_to(owner), finish using it before " \
                            "shrinking, or keep an index instead of a view"
        end
      end
    end
    if !@text_only && (call = @unproved.first?)
      call.raise "cannot prove opaque callback retain/escape effects; " \
                 "use a directly known callback inside the owning scope, " \
                 "or pass independently owned data instead of tape views"
    end
  end

  # Types are fixed after semantic cleanup; classify each identity once.
  @type_names = Hash(Type, String).new

  private def type_name(type : Type) : String
    @type_names[type] ||= type.to_s
  end

  @storage_type_cache = Hash(Type, Bool).new

  private def storage_type?(type : Type?) : Bool
    return storage_type_uncached(type) unless type
    @storage_type_cache.fetch(type) do
      @storage_type_cache[type] = storage_type_uncached(type)
    end
  end

  @reference_type_cache = Hash(Type, Bool).new

  private def reference_type?(type : Type?) : Bool
    return reference_type_uncached(type) unless type
    @reference_type_cache.fetch(type) do
      @reference_type_cache[type] = reference_type_uncached(type)
    end
  end

  @value_holder_cache = Hash(Type, Bool).new

  private def value_holder?(type : Type?) : Bool
    return value_holder_uncached(type) unless type
    @value_holder_cache.fetch(type) do
      @value_holder_cache[type] = value_holder_uncached(type)
    end
  end

  @proc_type_cache = Hash(Type, Bool).new

  private def proc_type?(type : Type?) : Bool
    return proc_type_uncached(type) unless type
    @proc_type_cache.fetch(type) do
      @proc_type_cache[type] = proc_type_uncached(type)
    end
  end

  private def storage?(node : ASTNode) : Bool
    storage_type?(node.type?)
  end

  private def storage_type_uncached(type : Type?) : Bool
    name = type.try { |t| type_name(t.remove_typedef) } || ""
    name == "String::Builder" || name.starts_with?("Array(") ||
      name.starts_with?("Hash(") || name.starts_with?("RisTree(")
  end

  private def reference?(node : ASTNode) : Bool
    reference_type?(node.type?)
  end

  private def reference_type_uncached(type : Type?) : Bool
    return true if storage_type?(type)
    return false unless type
    name = type_name(type.remove_typedef)
    name == "String" || name == "String::Span" || name.starts_with?("Array::Link(") || name.includes?("View(") || name.includes?("Iterator") ||
      name.starts_with?("Pointer(") || !!TapeChecker.tape_in(@program, type)
  end

  private def merge(a : Value, b : Value) : Value
    if a == EMPTY && b == EMPTY
      EMPTY
    else
      Value.new((a.roots + b.roots).uniq, (a.views + b.views).uniq,
        (a.procs + b.procs).uniq, a.unknown_proc || b.unknown_proc)
    end
  end

  # Back edges forget branch choices: the next round can take another
  # branch. Birth positions are canonical while solving, chronological
  # while checking. Allocation roots are AST identities, so this lattice
  # (roots, view roots and proc identities) is finite.
  private def loop_env(env : Env, born : Int32? = nil) : Env
    transform = ->(v : Value) do
      Value.new(v.roots, v.views.map { |x|
        View.new(x.root, born ? Math.min(born, x.born) : x.born,
          @guards.dup, x.index)
      }.uniq, v.procs, v.unknown_proc)
    end
    Env.new(env.vars.transform_values { |v| transform.call(v) },
      env.slots.transform_values { |v| transform.call(v) })
  end

  private def join_env(a : Env, b : Env) : Env
    result = a.dup
    b.vars.each { |key, v| result[key] = merge(result[key]? || EMPTY, v) }
    b.slots.each { |key, v| result.slots[key] = merge(result.slots[key]? || EMPTY, v) }
    result
  end

  private def loop_value(body : ASTNode, env : Env,
                         cond : ASTNode? = nil, kind = "loop round") : Value
    @scopes << body.object_id
    # A marked body frees its scratch at its end (SPEC 1.1).
    scoped = !TapeScopeChecker.parts(body).nil?
    if scoped
      @tape_blocks << body.object_id
      @tape_kinds[body.object_id] = kind
    end
    start = @uses.size
    shrink_start = @shrinks.size
    returns = @returns
    kept_returns = @kept_returns
    entry = loop_env(env, start)
    head = entry
    loop do
      round = head.dup
      value(cond, round) if cond
      value(body, round)
      # Join with the last head, not the entry: a round that rebinds a
      # variable must not drop what earlier rounds made live, or the
      # state swings back and forth and never settles.
      updated = loop_env(join_env(head, round), start)
      # Speculative rounds establish the environment, not event order.
      @uses.truncate(0, start)
      @shrinks.truncate(0, shrink_start)
      @returns = returns
      @kept_returns = kept_returns
      break if updated == head
      head = updated
    end
    round = head.dup
    result = EMPTY
    2.times do
      value(cond, round) if cond
      result = value(body, round)
      round = loop_env(round)
    end
    # A while condition is evaluated once more on the exit edge.
    value(cond, round) if cond
    joined = join_env(head, round)
    joined.vars.each { |key, v| env[key] = v }
    joined.slots.each { |key, v| env.slots[key] = v }
    @scopes.pop
    if scoped
      @tape_blocks.pop
      # A local first bound in the round to the round's data is gone
      # with the round: reading it after the loop is refused.
      if kind == "loop round" && @checking && !@text_only
        joined.vars.each do |key, v|
          next if key.starts_with?("#") || key.starts_with?("__")
          declaration = joined["#binding:#{key}"]?
          next unless declaration
          next unless declaration.roots.any? { |r| root_scope(r).includes?(body.object_id) }
          if source_roots(v).any? { |r| (blocks = root_tapes_of(r)) && blocks.includes?(body.object_id) }
            @dead[key] = body
          end
        end
      end
    end
    result
  end

  # The scopes *root* was made in, outermost first.
  private def root_tapes_of(root : UInt64) : Array(UInt64)?
    declaration = root
    while true
      if blocks = @root_tape_sets[declaration]?
        return blocks
      end
      parent = @parents[declaration]?
      return nil unless parent
      declaration = parent[0]
    end
  end

  # A def's result or a block's value leaves *scope* through RESULT: a
  # String or Array made there moves down to the caller's boundary; any
  # other value made there would have to be copied out, which is refused
  # (SPEC 1.9). What it views from outside is checked as a store.
  # Roots a copy_to or to_heap made: they are on their owner.
  @copied_roots = Set(UInt64).new

  private def check_leaving(scope : UInt64, v : Value, env : Env,
                            type : Type?, node : ASTNode) : Nil
    return unless @checking && !@text_only
    complete = stored(v, env)
    flat = flat_result?(type)
    # A struct value is returned by value: what it holds is in its
    # slots' views. A class instance or storage handle is on the tape.
    sources = flat ? complete.views.map(&.root).reject { |r| complete.roots.includes?(r) } : source_roots(complete).reject { |r| struct_value?(r) }
    # A String's views are its own bytes, which move with it.
    sources = [] of UInt64 if text_result?(type)
    sources.each do |source|
      blocks = root_tapes_of(source)
      if flat
        next unless blocks && blocks.includes?(scope)
      else
        # Unknown is refused: what a non-flat value holds must come from
        # a parameter, `self` or program data.
        next if from_caller?(source)
        # A block's value made before the block (the def's builder that
        # its block appends to) is older than the block's scratch.
        next if !node.is_a?(Def) && blocks && !blocks.includes?(scope)
      end
      next if @copied_roots.includes?(source)
      what = node.is_a?(Def) ? "def `#{node.name}`" : "block"
      refuse node, "cannot return a value made in this #{what}'s scratch: " \
                 "it would have to be copied out (SPEC 1.9).\nEnd the def " \
                 "with the call alone, append to a String or Array " \
                 "parameter, grow a local in place and return it, or " \
                 "write copy_to(owner)", root_name(source)
    end
  end

  # A String, or an Array whose elements hold no tape storage made with
  # it: what moves down in one memmove. Non-tape values hold no roots.
  private def flat_result?(type : Type?) : Bool
    return true unless type
    type = type.remove_typedef
    if type.is_a?(UnionType)
      return type.union_types.all? { |t| flat_result?(t) }
    end
    # A class instance is on the tape it was made on, fields or not.
    return false if class_instance?(type)
    return true unless TapeChecker.tape_in(@program, type)
    name = type_name(type)
    name == "String" || name.starts_with?("Array(")
  end

  # An instance of a class: `new` put it on the running tape (SPEC 1.3).
  private def class_instance?(type : Type) : Bool
    type.is_a?(InstanceVarContainer) && !type.struct? && !type.is_a?(PrimitiveType) &&
      !type.is_a?(MetaclassType) && type_name(type) != "String" &&
      !type.is_a?(UnionType) && !type.is_a?(VirtualMetaclassType)
  end

  # Whether *root* is storage the caller handed in or program data.
  private def from_caller?(root : UInt64) : Bool
    declaration = root
    while true
      return true if @parameter_roots.includes?(declaration) ||
                     @global_ids.includes?(declaration)
      parent = @parents[declaration]?
      return false unless parent
      declaration = parent[0]
    end
  end

  # A one-call def builds its value in this scope (SPEC 1.5): a non-flat
  # value it answers with no storage its summary can name is taken as
  # made here, so it cannot leave unchecked (unknown is refused).
  private def handed_on(node : ASTNode, result : Value) : Value
    return result unless @checking && !@text_only && !@tape_blocks.empty?
    return result unless node.is_a?(Call) && result.views.empty?
    # The call's own root, with no slot views behind it: a struct whose
    # fields the summary does not name is no plain value either.
    own = result.roots == [node.object_id]
    return result unless result.roots.empty? || own
    type = node.type?
    return result unless type && TapeChecker.tape_in(@program, type) && !flat_result?(type)
    targets = @graph.targets(node)
    return result unless targets && targets.any? do |t|
      !t.is_a?(External) && !TapeScopeChecker.constructor?(t) &&
        TapeScopeChecker.parts(t.body).nil? && TapeScopeChecker.one_call?(t.body) &&
        !TapeRules.runtime?(@program, t.location)
    end
    if own
      # Only a call that allocates can have put fresh storage in it.
      @handed << node.object_id if targets.any? { |t| @graph.allocates?(t.body) }
      return result
    end
    @root_scopes[node.object_id] = @scopes.dup
    @root_types[node.object_id] = type
    @root_births[node.object_id] = @uses.size
    note_fresh(node.object_id)
    @handed << node.object_id
    Value.new([node.object_id], [] of View)
  end

  @handed = Set(UInt64).new

  # An @[OnTape] struct: a value whose fields may hold tape storage.
  private def tape_struct?(type : Type) : Bool
    type = type.remove_typedef
    type.struct? && !type.is_a?(UnionType) && type_name(type) != "String" &&
      !!TapeChecker.tape_in(@program, type)
  end

  # Struct values whose `new` allocated (a Params making its Arrays): what
  # they hold was made with them, so they are no plain value.
  @allocating_structs = Set(UInt64).new

  private def struct_value?(root : UInt64) : Bool
    return false if @handed.includes?(root) || @allocating_structs.includes?(root)
    return false unless type = @root_types[root]?
    plain_struct?(type.remove_typedef)
  end

  # A struct holding no storage handle of its own (its tape fields have
  # slots), or a union of such structs and Nil (an error or none).
  private def plain_struct?(type : Type) : Bool
    if type.is_a?(UnionType)
      members = type.union_types.reject(&.nil_type?)
      return !members.empty? && members.size < type.union_types.size + 1 &&
        members.all? { |t| !t.is_a?(UnionType) && plain_struct?(t.remove_typedef) }
    end
    type.struct? && !storage_type?(type) && type_name(type) != "String" &&
      !type.is_a?(PrimitiveType)
  end

  private def foreign_view?(node : Call) : Bool
    node.name == "new" && node.args.size == 2 && !node.block &&
      node.type?.try { |t| type_name(t.remove_typedef) } == "String" &&
      node.args[0].type?.try(&.remove_typedef.is_a?(PointerInstanceType)) || false
  end

  # A String, or a union whose only tape member is String.
  # An expression whose value is a String itself (not a union): the
  # last one of a body counts.
  private def moved_text?(node : ASTNode) : Bool
    while node.is_a?(Expressions) && !node.expressions.empty?
      node = node.expressions.last
    end
    return false unless t = node.type?
    moved_type?(t.remove_typedef)
  end

  # A String, an error struct holding one, or a union of those and
  # plain values: what `__iyi_scope_result` moves down whole.
  private def moved_type?(t : Type) : Bool
    if t.is_a?(UnionType)
      return t.union_types.all? { |m|
        m = m.remove_typedef
        type_name(m) == "String" || one_text_struct?(m) || flat_array?(m) || !TapeChecker.tape_in(@program, m)
      }
    end
    type_name(t) == "String" || one_text_struct?(t) || flat_array?(t)
  end

  # An Array of plain values: `__iyi_scope_result` moves it down whole.
  private def flat_array?(t : Type) : Bool
    type_name(t).starts_with?("Array(") && t.is_a?(GenericClassInstanceType) &&
      t.type_vars["T"]?.try { |v| (vt = v.as?(Var).try(&.type?)) && !TapeChecker.tape_in(@program, vt.remove_typedef) } == true
  end

  # A body whose last expression is a `return`: its value is a return's,
  # judged with the others.
  private def ends_in_return?(node : ASTNode) : Bool
    while node.is_a?(Expressions) && !node.expressions.empty?
      node = node.expressions.last
    end
    # A `while true` that only returns ends no other way either.
    node.is_a?(Return) || !!node.type?.try(&.no_return?)
  end

  # A struct whose tape fields are Strings and whose others are plain
  # numbers, booleans or enums: `__iyi_scope_result` moves its Strings
  # down as a String result's (an error and its sentence).
  private def one_text_struct?(type : Type, depth = 0) : Bool
    # A Tuple of Strings and plain values moves the same way
    # (`__iyi_tuple_move`).
    if type.is_a?(TupleInstanceType)
      members = type.tuple_types.map(&.remove_typedef)
      return members.any? { |m| type_name(m) == "String" } && members.all? { |m|
        type_name(m) == "String" || m.is_a?(IntegerType) || m.is_a?(FloatType) ||
          m.is_a?(BoolType) || m.is_a?(EnumType) || m.is_a?(CharType) || m.nil_type?
      }
    end
    return false unless type.struct? && type.is_a?(InstanceVarContainer) && !type.is_a?(UnionType)
    texts = 0
    type.all_instance_vars.each_value do |ivar|
      it = ivar.type?.try(&.remove_typedef)
      return false unless it
      # `T?`: what `__iyi_text_move` moves as T (a String, or one level
      # down a struct of texts).
      if it.is_a?(UnionType)
        members = it.union_types.map(&.remove_typedef).reject(&.nil_type?)
        return false unless members.size == 1 && members.size < it.union_types.size
        it = members.first
      end
      if type_name(it) == "String"
        texts += 1
      elsif depth == 0 && one_text_struct?(it, 1)
        texts += 1
      elsif TapeChecker.tape_in(@program, it) || !(it.is_a?(IntegerType) || it.is_a?(FloatType) || it.is_a?(BoolType) || it.is_a?(EnumType) || it.is_a?(CharType) || it.nil_type?)
        return false
      end
    end
    texts >= 1
  end

  private def union_with_text?(type : Type?) : Bool
    type = type.try(&.remove_typedef)
    type.is_a?(UnionType) && type.union_types.any? { |t|
      t = t.remove_typedef
      type_name(t) == "String" || one_text_struct?(t) || flat_array?(t)
    }
  end

  private def text_result?(type : Type?) : Bool
    return false unless type
    type = type.remove_typedef
    members = type.is_a?(UnionType) ? type.union_types : [type]
    tape = members.select { |t| TapeChecker.tape_in(@program, t) }
    !tape.empty? && tape.all? { |t| type_name(t.remove_typedef) == "String" }
  end

  # Whether *source* leaves with the def's result being checked: made in
  # the def, or a scope inside it, which RESULT frees and moves past.
  private def leaving?(source : UInt64) : Bool
    return false unless scope = @leaving
    (root_tapes_of(source) || [] of UInt64).includes?(scope)
  end

  private def summary_marked?(target : Def) : Bool
    !TapeScopeChecker.parts(target.body).nil?
  end

  private def use(v : Value, node : ASTNode, holder = "")
    @uses << Use.new(v.views, node, @guards.dup, holder)
  end

  private def proc_type_uncached(type : Type?) : Bool
    return false unless type
    type = type.remove_typedef
    return type.union_types.any? { |member| proc_type?(member) } if type.is_a?(UnionType)
    type.is_a?(ProcInstanceType)
  end

  def value(node : ASTNode, env : Env) : Value
    result = evaluate(node, env)
    result = tape_text(node, result)
    result = handed_on(node, result)
    if node.is_a?(Call) && link_type?(node.type?) && !result.views.empty?
      result = Value.new(result.roots,
        result.views.map(&.copy_with(index: true)), result.procs,
        result.unknown_proc)
    end
    if proc_type?(node.type?) && result.procs.empty?
      Value.new(result.roots, result.views, result.procs, true)
    else
      result
    end
  end

  private def link_type?(type : Type?) : Bool
    !!type.try { |t| type_name(t.remove_typedef).starts_with?("Array::Link(") }
  end

  private def possible_array?(type : Type?) : Bool
    return true unless type
    type = type.remove_typedef
    return type.union_types.any? { |t| possible_array?(t) } if type.is_a?(UnionType)
    type.to_s.starts_with?("Array(")
  end

  # A class instance's Array field, or any instance's builder, is its own
  # component, never a pool run: it grows in place in its own
  # reservation (SPEC 2.2).
  private def class_field_root?(root : UInt64) : Bool
    return false unless parent = @parents[root]?
    return false unless parent[1].starts_with?('@')
    type = one_class(root_type(parent[0]))
    return true if type.is_a?(NonGenericClassType) && !type.struct?
    type.is_a?(InstanceVarContainer) &&
      type_name(type.instance_vars[parent[1]]?.try(&.type?).try(&.remove_typedef) || type) == "String::Builder"
  end

  # *type* without its typedef, and a field that may be nil (a reader's
  # decoder) as its one class.
  private def one_class(type : Type?) : Type?
    type = type.try(&.remove_typedef)
    if type.is_a?(NilableType)
      type.not_nil_type.remove_typedef
    elsif type.is_a?(UnionType)
      others = type.union_types.reject(&.nil_type?)
      others.size == 1 ? others.first.remove_typedef : type
    else
      type
    end
  end

  # A callee summary root's type, from the target's owner or parameter
  # down its fields: a caller's path may fold deeper fields onto an
  # ancestor, so the callee's own path says what the field is.
  private def summary_root_type(root : UInt64, summary : Summary, target : Def) : Type?
    if i = summary.seeds.index(root)
      return target.owner? if i == 0
      return target.args[i - 1]?.try(&.type?)
    end
    return nil unless parent = @parents[root]?
    type = one_class(summary_root_type(parent[0], summary, target))
    return nil unless type.is_a?(InstanceVarContainer)
    type.instance_vars[parent[1]]?.try(&.type?)
  end

  # Whether *type*, a class instance's field (the root's parent a class),
  # is an Array of scalars or a struct holding no storage of its own.
  private def flat_field_type?(type : Type?, root : UInt64) : Bool
    return false unless type
    return false unless parent = @parents[root]?
    return false unless parent[1].starts_with?('@')
    type = type.remove_typedef
    return true if type.is_a?(NonGenericClassType) && type.struct? &&
                   !storage_type?(type)
    return false unless type.is_a?(GenericClassInstanceType)
    return false unless type_name(type).starts_with?("Array(")
    element = type.type_vars["T"]?.try { |v| v.as?(Var).try(&.type?) }
    !element.nil? && !reference_type?(element) && !storage_type?(element)
  end

  # A class instance's Array of scalars (a byte stage) or struct value:
  # growing or writing it stores no storage of the scope that runs the
  # call. A struct's reference fields have slots of their own.
  private def flat_array_field?(root : UInt64) : Bool
    return false unless class_field_root?(root)
    type = root_type(root).try(&.remove_typedef)
    return true if type.is_a?(NonGenericClassType) && type.struct? &&
                   !storage_type?(type)
    return false unless type.is_a?(GenericClassInstanceType)
    return false unless type_name(type).starts_with?("Array(")
    element = type.type_vars["T"]?.try { |v| v.as?(Var).try(&.type?) }
    !element.nil? && !reference_type?(element) && !storage_type?(element)
  end

  private def parameter_root?(root : UInt64) : Bool
    return true if @parameter_roots.includes?(root)
    @parents[root]?.try { |parent| parameter_root?(parent[0]) } || false
  end

  private def global_value(key : UInt64, type : Type?) : Value
    return EMPTY unless reference_type?(type)
    root = @global_roots[key] ||= fresh
    @global_ids << root
    @root_types[root] = type if type
    Value.new([root], [] of View)
  end

  private def evaluate(node : ASTNode, env : Env) : Value
    case node
    when MacroIf, MacroFor, MacroExpression, MacroVerbatim
      node.expanded.try { |expanded| value(expanded, env) } || EMPTY
    when Expressions
      result = EMPTY
      mark = @guards.size
      node.expressions.each do |exp|
        @fallthrough = Guards.new
        result = value(exp, env)
        @guards.concat(@fallthrough) if exp.is_a?(If) || exp.is_a?(Expressions)
      end
      # A branch that left (`if ... return`) guards the rest of the block,
      # and what follows the block too.
      @fallthrough = @guards[mark..]
      @guards.pop(@guards.size - mark)
      result
    when Path
      if constant = node.target_const
        global_value(constant.object_id, node.type?)
      else
        EMPTY
      end
    when ClassVar, Global
      global_value(node.var.object_id, node.type?)
    when Var, InstanceVar
      if node.is_a?(Var) && (loop_body = @dead[node.name]?) && @checking && !@text_only
        refuse node, "cannot read `#{node.name}` after the loop: its value was " \
                   "made in a loop round, which frees it at its end (SPEC " \
                   "1.1).\nRead the value before the loop ends, or copy it " \
                   "with copy_to(owner)"
      end
      # A local proc keeps its known literal even when its type holds no
      # tape storage (a `String::Builder` parameter, say).
      return EMPTY unless reference?(node) || proc_type?(node.type?)
      v = env[node.name] ||= if node.is_a?(InstanceVar)
                               Value.new((env["self"]? || EMPTY).roots.map { |r| field_root(r, node.name).as(UInt64) }, [] of View)
                             elsif reference?(node)
                               Value.new([node.object_id], [] of View)
                             else
                               EMPTY
                             end
      v.roots.each { |root| @root_types[root] ||= node.type }
      v = stored(v, env)
      if node.is_a?(Var) && node.type?.try { |t| flat_array?(t.remove_typedef) }
        # A narrowed Array of scalars cannot carry a sibling error arm's
        # text storage. Keep Array roots and unknown storage unchanged.
        text_arm = ->(root : UInt64) {
          root_type(root).try { |t| {"String", "String::Builder"}.includes?(type_name(t.remove_typedef)) } == true
        }
        v = Value.new(v.roots.reject { |r| text_arm.call(r) },
          v.views.reject { |view| text_arm.call(view.root) }, v.procs, v.unknown_proc)
      end
      if @text_only && node.is_a?(InstanceVar) && TapeChecker.possible_string?(node.type?) &&
         @program.ris_growing_field_names.includes?(node.name)
        # A separately checked method may read an already-grown field.
        # Until a store proves otherwise, it can borrow its companion.
        borrowed = v.roots.reject { |r| env.slots.has_key?(r) }.compact_map do |root|
          if parent = @parents[root]?
            view(field_root(parent[0], "@__ris_text_#{node.name.lchop('@')}"))
          end
        end
        v = Value.new(v.roots, (v.views + borrowed).uniq)
      end
      use(v, node)
      v
    when Assign
      # Legacy shrink analysis predates this compiler-only operation.
      # The original assignment already binds the new text; its copying
      # reset is checked exclusively by the private text analysis.
      if !@text_only && (call = node.value).is_a?(Call) &&
         ((call.name == "__ris_text_reset" &&
           call.obj.try(&.type?.try(&.to_s)) == "RisTextGrowth") ||
          (node.target.is_a?(InstanceVar) &&
           call.name == "__ris_text_reset_#{node.target.as(InstanceVar).name.lchop('@')}"))
        return EMPTY
      end
      v = value(node.value, env)
      target = node.target
      if target.is_a?(InstanceVar)
        # Scalar fields cannot hold storage or borrows. Exporting empty
        # scalar slots made call summaries manufacture every combination
        # of irrelevant field paths through recursive receiver graphs.
        return v if target.type? && !reference?(target)
        roots = (env["self"]? || EMPTY).roots.map { |r| field_root(r, target.name).as(UInt64) }
        # Fresh growing fields are built into their own slot. A borrowed
        # handle instead keeps the identity of the storage it aliases.
        fresh_field = storage?(node.value) && @graph.fresh?(node.value)
        contents = fresh_field ? EMPTY : v
        refuse_fresh_store(roots, node) if fresh_field
        store(roots, contents, env, node)
      elsif target.is_a?(Var)
        if target.name.starts_with?("__")
          env[target.name] = v
        else
          bind(target, v, env, node)
        end
      end
      v
    when TypeDeclaration
      if exp = node.value
        v = value(exp, env)
        target = node.var
        bind(target, v, env, node) if target.is_a?(Var)
        v
      else
        EMPTY
      end
    when While, Until
      loop_value(node.body, env, node.cond)
    when Cast
      value(node.obj, env)
    when Call
      return value(node.expanded.not_nil!, env) if node.expanded
      # Specialized-out branches retain syntax without executable targets.
      return EMPTY unless node.type?
      # `String.new(pointer, size)` views bytes it does not own (std's
      # mapped files, FFI buffers): it makes nothing on the tape.
      if foreign_view?(node)
        node.args.each { |arg| value(arg, env) }
        return EMPTY
      end
      if node.name == "new"
        # A local container can hold an owner declared in the same scope.
        # Parameter and program roots still carry their longer lifetimes.
        @root_scopes[node.object_id] = @scopes.dup
        @root_types[node.object_id] = node.type
        @root_births[node.object_id] = @uses.size
        note_fresh(node.object_id)
      end
      if @text_only && node.name.in?("copy_to", "new", "dup") &&
         TapeChecker.possible_string?(node.type?)
        @text_copies << node.object_id
      end
      # A call to a top-level def (`::f`, or one the Program owns) takes no
      # self: the caller's self is no input of it.
      top_level = node.global? || (@graph.targets(node).try do |found|
        !found.empty? && found.all? { |t| t.owner?.is_a?(Program) }
      end || false)
      receiver = node.obj.try { |obj| value(obj, env) } ||
                 (top_level ? EMPTY : env["self"]?) || EMPTY
      args = node.args.map { |arg| value(arg, env) }
      named = Hash(String, Value).new
      node.named_args.try &.each do |arg|
        named[arg.name] = v = value(arg.value, env)
        args << v
      end
      node.block_arg.try { |arg| args << value(arg, env) }
      # Scope reception preserves borrowed identities; fresh results may
      # be copied, so forwarding the original is conservative. The global
      # wrapper must not turn an implicit self into a result dependency.
      if @text_only && node.global?
        return args.last? || EMPTY if node.name == TapeScopeChecker::RESULT
        return EMPTY if node.name.in?(TapeScopeChecker::MARK,
          TapeScopeChecker::RESET, TapeScopeChecker::RESULT_AT)
      end
      # Growing text's companion is its stable reservation identity.
      # Reset has the same invalidation rule as Array#clear. Call summaries
      # carry this effect through methods and field accessors.
      if node.obj.try(&.type?.try(&.to_s)) == "RisTextGrowth"
        if !@text_only && node.name == "__ris_text_reset"
          return args.first? || EMPTY
        end
        # Growing text appends a copy of its argument's bytes: the result
        # views the text grown (its first argument), never the argument.
        if !@text_only && node.name == "append"
          args.each { |arg| use(arg, node) }
          return args.first? || EMPTY
        end
      end
      if @text_only && node.obj.try(&.type?.try(&.to_s)) == "RisTextGrowth"
        @text_roots.concat(receiver.roots)
        if node.name == "__ris_text_reset"
          return args.first? || EMPTY unless TapeChecker.possible_string?(node.type?)
          text_reset(receiver.roots, node, env, chain("text reset"))
          args.each { |arg| use(arg, node) }
          # With no writer yet, runtime returns the input unchanged.
          # Keep that possible borrow as well as the reservation view.
          return merge(args.first? || EMPTY, Value.new(receiver.roots,
            receiver.roots.map { |root| view(root) }))
        elsif node.name == "append"
          return Value.new(receiver.roots,
            receiver.roots.map { |root| view(root) })
        end
      end
      storage_receiver = node.obj.try { |obj| storage?(obj) } ||
                         @graph.targets(node).try &.any? { |target| storage_type?(target.owner) }
      if storage_receiver && {"<<", "push", "concat", "append", "write_bytes", "unshift"}.includes?(node.name)
        shrink(receiver.roots, node, chain(node.name), true)
      end
      if storage_receiver && {"[]=", "__loop_store", "unchecked_store"}.includes?(node.name) &&
         node.obj.try do |obj|
           name = obj.type?.try(&.to_s) || ""
           name.starts_with?("Array(Array(") || name == "Array(String)" ||
             name.starts_with?("Hash(")
         end
        shrink(receiver.roots, node, chain(node.name))
      end
      if storage_receiver && SHRINK.includes?(node.name)
        shrink(receiver.roots, node, chain(node.name))
        if node.name == "clear" && receiver.roots.size == 1 &&
           !@folded_roots.includes?(receiver.roots.first)
          env.slots.reject! do |key, _|
            contains_root?(receiver.roots, key)
          end
        end
      end
      if storage_receiver && {"<<", "push", "[]=", "__loop_store", "unchecked_store"}.includes?(node.name)
        # A scalar element (a byte into an Array(UInt8)) holds no storage:
        # it is no store a summary should carry.
        # A builder's (or a String grown in place's) `<<` copies the
        # text's bytes: it keeps no view of it.
        builder_copy = node.name == "<<" &&
                       node.obj.try(&.type?).try { |t| {"String::Builder", "String"}.includes?(type_name(t)) }
        if (element = args.last?) && !builder_copy && node.args.last?.try { |arg| reference?(arg) } != false
          store(receiver.roots.map { |r| field_root(r, "[]").as(UInt64) }, element, env, node, false)
        end
      end
      element_result : Value? = nil
      if node.obj.try do |obj|
           obj.type?.try do |t|
             name = type_name(t)
             name.starts_with?("Array(") || name.starts_with?("Hash(")
           end
         end &&
         {"[]", "[]?", "first", "first?", "last", "last?", "fetch", "__loop_fetch"}.includes?(node.name)
        elements = receiver.roots.map { |r| field_root(r, "[]").as(UInt64) }
        if storage?(node)
          @pooled_roots.concat(elements)
          elements.each { |root| @root_types[root] = node.type }
          element_result = Value.new(elements, [] of View)
        elsif !elements.empty? && elements.all? { |r| env.slots.has_key?(r) }
          element_result = elements.reduce(EMPTY) do |result, root|
            contents = value_holder?(node.type?) ? Value.new([root], [] of View) : env.slots[root]
            merge(result, stored(contents, env))
          end
        end
      end
      inputs = [receiver] + args
      call_result = EMPTY
      result_fields = [] of UInt64
      summarized = false
      incomplete_result = false
      reset_roots = [] of UInt64
      targets = @graph.targets(node)
      # What the receiver's fields held before the call: a callee that
      # clears and refills them drops these from the caller's slots.
      held_before = [] of View
      if !@text_only && !receiver.roots.empty? && targets && !targets.empty?
        env.slots.each do |key, contents|
          held_before.concat(contents.views) if contains_root?(receiver.roots, key)
        end
      end
      if targets && !targets.empty?
        before_calls = env
        after_calls : Env? = nil
        targets.each do |target|
          summary = summary(target)
          call_env = summary && !summary.stores.empty? ? before_calls.dup : before_calls
          boundary = target.is_a?(External) || @graph.proc_call?(target) ||
                     (target.iyi_from_artifact? && !target.iyi_body_travelled?)
          if boundary && target.iyi_from_artifact? && !target.ris_call_contract
            node.raise "imported def lacks a checked tape contract; rebuild the module with --emit-iyimod"
          end
          if boundary && (checked = @graph.contract(target))
            # A directly known proc is executed below with its environment.
            unless @graph.proc_call?(target) && !receiver.procs.empty? && !receiver.unknown_proc
              actuals = [receiver] + target.args.map_with_index do |arg, i|
                named[arg.external_name]? || args[i]? || EMPTY
              end
              summarized = true
              checked.parameters.each_with_index do |bits, i|
                # Field paths also model ordinary heap/scalar values. Only
                # a tape-capable formal can carry a borrowed storage effect.
                borrowed = i == 0 ? reference_type?(target.owner?) : reference?(target.args[i - 1])
                next unless borrowed
                input = actuals[i]? || EMPTY
                roots = source_roots(input).flat_map { |r| aliases(r, env) }.uniq
                # An unknown proc's argument: what its type's methods can
                # do decides (`handed_effect`); an object's effect is on
                # its fields, so a reference to it stays valid.
                handed = @graph.proc_call?(target) && i > 0 ? proc_argument_type(target, i - 1) : nil
                # A constructor's receiver is the value `new` just made:
                # no view of it exists yet for the constructor's own field
                # growth to move (an imported `initialize` filling Arrays).
                constructing = i == 0 && TapeScopeChecker.constructor?(target) && !handed
                if bits & TapeCallGraph::Contract::SHRINK != 0 && !constructing
                  if found = handed ? handed_effect(handed, false) : WHOLE
                    shrunk = found == WHOLE ? roots : roots.flat_map { |r| found.map { |f| handed_field(r, f) } }.uniq
                    shrink(shrunk, node, chain("#{node.name} (opaque contract)"))
                  end
                end
                if bits & TapeCallGraph::Contract::RETAIN != 0 && !roots.empty?
                  if found = handed ? handed_effect(handed, true) : WHOLE
                    kept = found == WHOLE ? roots : roots.flat_map { |r| found.map { |f| handed_field(r, f) } }.uniq
                    @retains.concat(kept)
                    @unproved << node if @checking
                  end
                end
                if bits & TapeCallGraph::Contract::STORE_SELF != 0
                  destinations = receiver.roots.flat_map { |r| aliases(r, call_env) }.uniq
                  store(destinations, input, call_env, node, replace: false)
                end
                if bits & TapeCallGraph::Contract::RESULT != 0
                  call_result = merge(call_result, input)
                end
              end
            end
          elsif summary
            # A proc obtained from a summary can execute a body outside
            # the lexical call tree. Record the summaries it reads too.
            if caller = @solving
              (@summary_callers[target.object_id] ||= Set(UInt64).new) << caller
            end
            summarized = true
            actuals = [receiver] + target.args.map_with_index do |arg, i|
              named[arg.external_name]? || args[i]? || EMPTY
            end
            summary.shrinks.each do |root, chain|
              roots = translate(root, summary, actuals).flat_map { |r| aliases(r, env) }.uniq
              if @text_only && chain.includes?("text reset")
                reset_roots.concat(roots)
                text_reset(roots, node, env,
                  chain("#{node.name} -> #{chain}"))
              else
                shrink(roots, node, chain("#{node.name} -> #{chain}"))
                # A callee that clears a field empties it: what the caller
                # knew it held is gone, as after a direct `clear`.
                if !@text_only && chain.ends_with?("clear") && roots.size == 1 &&
                   !@folded_roots.includes?(roots.first)
                  call_env.slots.reject! { |key, _| contains_root?(roots, key) }
                end
              end
            end
            summary.grows.each do |root, cause|
              roots = translate(root, summary, actuals).flat_map do |r|
                aliases(r, env)
              end.uniq
              shrink(roots, node, chain("#{node.name} -> #{cause}"), true)
            end
            retained = summary.retains.flat_map { |r| translate(r, summary, actuals) }
            @retains.concat(retained)
            @unproved << node if @checking && !retained.empty?
            # What the callee makes and answers is this call's allocation,
            # made here: inside any tape block around the call.
            # (Only a growing or text result: a callee that copies onto
            # another owner, `copy_to(Program.tape)`, answers no such thing.)
            # A tape struct (an @[OnTape] answer) holding what the callee
            # allocated is made here the same way.
            if !@tape_blocks.empty? && !{"copy_to", "to_heap"}.includes?(node.name) && (@graph.fresh?(node) ||
               (node.type?.try { |t| type_name(t.remove_typedef) == "String" || tape_struct?(t) } &&
                @graph.allocates?(node)))
              @root_scopes[node.object_id] ||= @scopes.dup
              note_fresh(node.object_id) unless @root_tapes.has_key?(node.object_id)
            end
            summary.stores.each do |root, contents|
              destinations = translate(root, summary, actuals, node.object_id)
              # A store whose contents do not reach this call - an object or
              # storage the callee made, which is on the running tape - put
              # into an object from outside a tape block: the block's
              # scratch is not proved private. (A copy into an Array's own
              # pool shows no contents either; it keeps the block's tape.)
              # Bytes pushed into a builder are copied into its own
              # reservation: its growth, not a store of what the callee made.
              builder = summary_root_type(root, summary, target).try { |t| type_name(t.remove_typedef) == "String::Builder" }
              refuse_fresh_store(destinations, node) if contents.roots.empty? && contents.views.empty? && !summary_marked?(target) && !destinations.all? { |d| flat_array_field?(d) } && !flat_field_type?(summary_root_type(root, summary, target), root) && !builder
              incoming = translated(contents, summary, actuals, node.object_id)
              # A marked callee's own scratch cannot reach its stores: it
              # refused that itself. What it made and stored is not this
              # scope's.
              if !@text_only && summary_marked?(target)
                incoming = Value.new(incoming.roots.reject { |r| r == node.object_id },
                  incoming.views.reject { |v| v.root == node.object_id },
                  incoming.procs, incoming.unknown_proc)
              end
              # A summary can write on only one branch. It cannot prove
              # that an older foreign text borrow was killed on every
              # path. Keep those borrows until a direct store kills them.
              # The reset's own current binding is the permitted holder.
              destinations.each do |destination|
                next unless @text_only
                previous = stored(call_env.slots[destination]? || EMPTY, call_env)
                kept = Value.new(previous.roots.select do |r|
                  text_root?(r) && !contains_root?(reset_roots, r)
                end, previous.views.select do |v|
                  text_root?(v.root) && !contains_root?(reset_roots, v.root)
                end)
                incoming = merge(incoming, kept)
              end
              @store_site = @store_sites[target.object_id]?.try &.[root]?
              begin
                store(destinations, incoming, call_env, node)
              ensure
                @store_site = nil
              end
            end
            # Only a field load needs read-back. Roots forwarded from an
            # argument already name its storage, even when that storage is
            # itself a field of another owner.
            summary.result.roots.each do |root|
              if @parents.has_key?(root)
                result_fields.concat(translate(root, summary, actuals, node.object_id))
              end
            end
            call_result = merge(call_result, translated(summary.result, summary, actuals, node.object_id))
          else
            incomplete_result = true
            unless TapeRules.runtime?(@program, target.location)
              inputs.each { |v| shrink((v.roots + v.views.map(&.root)).uniq, node, chain("#{node.name} (opaque)")) }
            end
          end
          after_calls = after_calls.try { |previous| join_env(previous, call_env) } || call_env
        end
        if (joined = after_calls) && !joined.same?(env)
          env.replace(joined)
        end
      elsif !TapeRules.runtime?(@program, node.location)
        inputs.each do |v|
          roots = source_roots(v)
          shrink(roots.uniq, node, chain("#{node.name} (unknown)"))
          @retains.concat(roots)
          @unproved << node if @checking && !roots.empty?
        end
      end
      # Arguments remain evaluated values until the call consumes them.
      consumed = @text_only ? Value.new(receiver.roots,
        receiver.views.reject { |v| contains_root?(reset_roots, v.root) },
        receiver.procs, receiver.unknown_proc) : receiver
      # What the receiver's fields hold is the callee's to order against
      # its own shrinks (a reader refilling its row): a summarized call
      # consumes the receiver, not the views its slots carry.
      if summarized && !@text_only && !receiver.roots.empty?
        held = env.slots.compact_map { |key, contents| contents.views if contains_root?(receiver.roots, key) }.flatten + held_before
        unless held.empty?
          consumed = Value.new(consumed.roots, consumed.views - held,
            consumed.procs, consumed.unknown_proc)
        end
      end
      use(consumed, node)
      args.each { |arg| use(arg, node) }
      derived = receiver
      # A builder's `<<` copies its argument and answers the builder: the
      # chained result views no argument storage.
      # A String grown in place copies the same way.
      copied = node.name == "<<" && !node.block &&
               node.obj.try(&.type?).try { |t| {"String::Builder", "String"}.includes?(type_name(t)) } &&
               {"String::Builder", "String"}.includes?(type_name(node.type))
      # String's `+` copies both sides into a new String: it views neither.
      concatenated = node.name == "+" && !node.block && node.args.size == 1 &&
                     node.obj.try(&.type?).try { |t| type_name(t) } == "String" &&
                     node.args[0].type?.try { |t| type_name(t) } == "String" &&
                     type_name(node.type) == "String"
      args.each { |arg| derived = merge(derived, arg) } unless copied
      if block = node.block
        outer = env.dup
        yielded_views = derived.views
        if VIEWS.includes?(node.name)
          yielded_views += receiver.roots.map { |root| view(root) }
        end
        yielded = Value.new(derived.roots, yielded_views)
        block.args.each { |arg| outer[arg.name] = reference?(arg) ? yielded : EMPTY }
        @callback_chain << "#{node.name} block"
        @scopes << block.object_id
        if node.name == "tape"
          explicit = node.name == "tape" && !node.obj
          if explicit
            @tape_blocks << block.object_id
            @tape_kinds[block.object_id] = "tape block"
          end
          block_value = value(block.body, outer)
          check_leaving(block.object_id, block_value, outer, block.body.type?, block) if explicit
          @tape_blocks.pop if explicit
        else
          block_value = loop_value(block.body, outer, kind: "block")
          # A program constant's initializer runs on the program's tape:
          # its value is the constant's, made on its owner.
          check_leaving(block.body.object_id, block_value, outer, block.body.type?, block) unless node.program_initializer?
        end
        @scopes.pop
        @callback_chain.pop
        use(yielded, block)
        env.keys.each { |key| env[key] = merge(env[key], outer[key]? || EMPTY) }
        (@text_only ? (env.slots.keys | outer.slots.keys) : env.slots.keys).each do |key|
          env.slots[key] = merge(env.slots[key]? || EMPTY,
            outer.slots[key]? || EMPTY)
        end
      end
      inputs.each do |input|
        input.procs.each do |literal|
          unless @active_procs.add?(literal.object_id)
            shrink(derived.roots, node,
              chain("#{node.name} (recursive callback)"))
            next
          end
          captured = env.dup
          # The callback may receive any of the call's tape arguments.
          literal.def.args.each { |arg| captured[arg.name] = Value.new(derived.roots, derived.views) }
          @callback_chain << "#{node.name} proc"
          loop_value(literal.def.body, captured)
          env.keys.each { |key| env[key] = merge(env[key], captured[key]? || EMPTY) }
          env.slots.each_key { |key| env.slots[key] = merge(env.slots[key], captured.slots[key]? || EMPTY) }
          @callback_chain.pop
          @active_procs.delete(literal.object_id)
        end
      end
      if {"[]", "view", "as_view", "slice_from", "new"}.includes?(node.name) &&
         type_name(node.type).starts_with?("Array::View(")
        source = node.name == "new" ? derived : receiver
        Value.new([] of UInt64,
          source.views + source.roots.map { |root| view(root) })
      elsif node.name == "new" && type_name(node.type).starts_with?("SlicePool::Run(")
        # A run borrows initialized slots from its Ary argument. Unlike
        # allocating constructors, it must retain that storage's lifetime.
        Value.new([] of UInt64,
          (derived.views + derived.roots.map { |root| view(root) }).uniq)
      elsif {"copy_to", "dup", "to_heap", "new"}.includes?(node.name) || concatenated
        if reference?(node)
          @root_scopes[node.object_id] = {"copy_to", "to_heap"}.includes?(node.name) ? [] of UInt64 : @scopes.dup
          # copy_to and to_heap put the copy on its owner, not here.
          note_fresh(node.object_id) unless {"copy_to", "to_heap"}.includes?(node.name)
          @copied_roots << node.object_id if {"copy_to", "to_heap"}.includes?(node.name)
          # A struct `new` holds what its arguments give it: a value it
          # returns carries their storage (SPEC 1.9).
          # (The constructor's own work, not its arguments': a struct
          # holding a copied sentence is still a plain value.)
          if node.name == "new" && @graph.targets(node).try(&.any? { |t| @graph.allocates?(t.body) })
            @allocating_structs << node.object_id
          end
          holder = node.name == "new" && struct_value?(node.object_id)
          borrowed = if @text_only && node.name.in?("new", "dup") &&
                        type_name(node.type) != "String"
                       derived.views + derived.roots.map { |root| view(root) }
                     elsif holder
                       args.flat_map { |a| a.views + a.roots.reject { |r| struct_value?(r) }.map { |root| view(root) } }
                     else
                       [] of View
                     end
          Value.new([node.object_id], borrowed.uniq)
        else
          EMPTY
        end
      elsif copying_text?(node)
        # Keep the same independence in call summaries as at call sites.
        # Formatting reads its inputs; it retains none of their storage.
        env.slots.reject! { |root, _| contains_root?([node.object_id], root) }
        @root_types[node.object_id] = node.type
        @root_scopes[node.object_id] = @scopes.dup
        note_fresh(node.object_id)
        Value.new([node.object_id], [] of View)
      elsif element_result && reference?(node)
        if storage?(node)
          element_result = merge(element_result,
            Value.new([] of UInt64, receiver.roots.map { |r| view(r) }))
        end
        use(element_result, node)
        element_result
      elsif summarized && reference?(node)
        call_result = merge(call_result, derived) if incomplete_result
        # Result views are born after the callee's shrinks. Stored views
        # keep their original birth when read back from a holder.
        call_result = Value.new(call_result.roots,
          call_result.views.map { |v| view(v.root) })
        if !storage?(node) && !VIEWS.includes?(node.name)
          call_result = read_slots(call_result, env, node.type?, result_fields)
        end
        call_result.roots.each { |r| @root_types[r] ||= node.type }
        if storage?(node)
          aliases = call_result.roots.flat_map do |root|
            (env.slots[root]?.try(&.roots) || [] of UInt64).reject do |source|
              # Constructor storage built into a field is represented by
              # its receiver until rebased here. It is not an alias of
              # every sibling field in that receiver.
              contains_root?([source], root)
            end
          end
          call_result = merge(call_result, Value.new(aliases, [] of View))
        end
        call_result = stored(call_result, env)
        views = call_result.views
        unless storage?(node) || value_holder?(node.type?)
          views += call_result.roots.reject { |r| env.slots.has_key?(r) }.map { |r| view(r) }
        end
        result = Value.new(call_result.roots, views)
        use(result, node)
        result
      elsif reference?(node)
        views = derived.views
        if VIEWS.includes?(node.name) || !storage?(node)
          views = views + derived.roots.map { |root| view(root) }
        end
        Value.new(storage?(node) ? derived.roots : [] of UInt64, views)
      else
        EMPTY
      end
    when If
      value(node.cond, env)
      left, right = env.dup, env.dup
      choice = fresh
      mark = @guards.size
      @guards << {choice, true}
      @scopes << node.then.object_id
      @fallthrough = Guards.new
      shrinks_before = @shrinks.size
      a = value(node.then, left)
      leave_branch(node.then, shrinks_before)
      then_after = node.then.is_a?(If) || node.then.is_a?(Expressions) ? @fallthrough : Guards.new
      @scopes.pop
      @guards.pop(@guards.size - mark)
      @guards << {choice, false}
      @scopes << node.else.object_id
      @fallthrough = Guards.new
      shrinks_before = @shrinks.size
      b = value(node.else, right)
      leave_branch(node.else, shrinks_before)
      else_after = node.else.is_a?(If) || node.else.is_a?(Expressions) ? @fallthrough : Guards.new
      @scopes.pop
      @guards.pop(@guards.size - mark)
      # What follows an If one of whose branches never falls through runs
      # only after the other: its events are on that branch's guard.
      left_leaves = node.then.type?.is_a?(NoReturnType)
      right_leaves = node.else.type?.is_a?(NoReturnType)
      @fallthrough = if left_leaves && !right_leaves
                       [{choice, false}] + else_after
                     elsif right_leaves && !left_leaves
                       [{choice, true}] + then_after
                     else
                       Guards.new
                     end
      (left.keys | right.keys).each { |key| env[key] = merge(left[key]? || EMPTY, right[key]? || EMPTY) }
      (left.slots.keys | right.slots.keys).each do |key|
        env.slots[key] = merge(left.slots[key]? || EMPTY, right.slots[key]? || EMPTY)
      end
      result = merge(a, b)
      boundary = node.object_id
      @root_scopes[boundary] = @scopes.dup
      store([boundary], result, env, node)
      result
    when Return
      result = node.exp.try { |exp| value(exp, env) } || EMPTY
      @returns = merge(@returns, result)
      @kept_returns = merge(@kept_returns, result) unless node.exp.try { |e| moved_text?(e) }
      result
    when Primitive
      node.name == "allocate" ? Value.new([node.object_id], [] of View) : EMPTY
    when ProcLiteral
      Value.new([] of UInt64, [] of View, [node])
    when ClassDef, ModuleDef
      value(node.body, Env.new)
    when Def, FunDef, Macro
      EMPTY
    else
      children = Children.new(self, env, node)
      node.accept children
      if reference?(node)
        use(children.result, node)
        children.result
      else
        EMPTY
      end
    end
  end

  class Children < Visitor
    getter result = EMPTY

    def initialize(@checker : TapeShrinkChecker, @env : Env, @root : ASTNode)
    end

    def visit(node : ASTNode)
      return true if node.same?(@root)
      @result = @checker.merge_child(@result, @checker.value(node, @env))
      false
    end
  end

  def merge_child(a : Value, b : Value) : Value
    merge(a, b)
  end
end
