# Intraprocedural view liveness. Events follow evaluation order, including
# the use of earlier operands when their enclosing call finally runs.
# Specialized call summaries converge before checking view liveness.
class Iyi::TapeShrinkChecker
  alias Guards = Array(Tuple(UInt64, Bool))
  record View, root : UInt64, born : Int32, guards : Guards = Guards.new
  # Roots name storage handles; views retain the storage a value borrows.
  # Holder slots carry those borrows separately so replacement can kill them.
  record Value, roots : Array(UInt64), views : Array(View),
    procs : Array(ProcLiteral) = [] of ProcLiteral,
    unknown_proc : Bool = false
  record Use, views : Array(View), node : ASTNode, guards : Guards
  record Shrink, roots : Array(UInt64), at : Int32, node : Call, chain : String,
    guards : Guards
  record Summary, seeds : Array(UInt64), shrinks : Hash(UInt64, String), result : Value,
    stores : Hash(UInt64, Value) = Hash(UInt64, Value).new,
    retains : Array(UInt64) = [] of UInt64
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
  VIEWS = {"finish", "span", "slice", "[]", "[]?", "first", "first?",
           "last", "last?", "fetch", "values_at", "to_unsafe", "to_slice",
           "iterator", "each", "each_with_index", "each_byte", "each_line"}
  @uses = [] of Use
  @shrinks = [] of Shrink

  # An owner has one named construction. Intern paths from that declaration
  # (or a call seed) so sibling fields never share an identity.
  @fields = Hash(Tuple(UInt64, String), UInt64).new
  @parents = Hash(UInt64, Tuple(UInt64, String)).new
  @next_root = 0_u64
  @returns = EMPTY
  @callback_chain = [] of String
  @active_procs = Set(UInt64).new
  @guards = Guards.new
  @root_births = Hash(UInt64, Int32).new
  @root_types = Hash(UInt64, Type).new
  @root_scopes = Hash(UInt64, Array(UInt64)).new
  @scopes = [] of UInt64
  @checking = false
  @unproved = [] of Call
  @retains = [] of UInt64

  # Slots live in the environment, so branch and loop joins include stores.
  private def root_birth(root : UInt64) : Int32
    @root_births[root]? || @parents[root]?.try { |p| root_birth(p[0]) } || 0
  end

  private def root_scope(root : UInt64) : Array(UInt64)
    @root_scopes[root]? || @parents[root]?.try { |p| root_scope(p[0]) } || [] of UInt64
  end

  private def stored(v : Value, env : Env) : Value
    result = v
    env.slots.each do |root, contents|
      if contains_root?(v.roots, root)
        result = merge(result, Value.new([] of UInt64, contents.views))
      end
    end
    result
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
    # Copy a by-value holder's slots, rather than baking its aggregate
    # roots into the parent. This lets an emptied nested field forget its
    # roots without changing a separate copy of the holder.
    copies = Hash(Array(String), Value).new
    carried = [] of View
    copied = [] of UInt64
    v.roots.each do |source|
      type = @root_types[source]?
      next unless value_holder?(type)
      env.slots.each do |root, contents|
        path = relative_path(root, source)
        next unless path && !path.empty?
        copies[path] = merge(copies[path]? || EMPTY, contents)
        carried.concat(contents.views)
        copied << source
      end
    end
    complete = stored(v, env)
    roots.each { |root| check_store(root, complete, node) }
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
      strong = replace && roots.size == 1
      if strong
        env.slots.reject! do |key, _|
          contains_root?([root], key)
        end
      end
      env.slots[root] = strong ? v : merge(env.slots[root]? || EMPTY, v)
      copies.each do |path, contents|
        destination = root
        path.each { |name| destination = field_root(destination, name) }
        env.slots[destination] = strong ? contents : merge(env.slots[destination]? || EMPTY, contents)
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
    v.roots.reject { |r| value_holder?(@root_types[r]?) } + v.views.map(&.root)
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
    if @checking
      destinations = root_scope(root)
      source_roots(v).each do |source|
        scope = source_scope(source)
        unless scope.all? { |part| destinations.includes?(part) }
          node.raise "cannot store a view beyond its owner scope; " \
                     "copy it with copy_to(owner) before storing it"
        end
      end
    end
  end

  private def bind(target : Var, v : Value, env : Env, node : ASTNode)
    binding = "#binding:#{target.name}"
    declaration = env[binding]? || begin
      @root_scopes[target.object_id] = @scopes.dup
      env[binding] = Value.new([target.object_id], [] of View)
    end
    declaration.roots.each { |root| check_store(root, stored(v, env), node) }
    env[target.name] = v
  end

  private def translated(v : Value, summary : Summary,
                         inputs : Array(Value), allocation : UInt64? = nil) : Value
    roots = v.roots.flat_map { |r| translate(r, summary, inputs, allocation) }.uniq
    views = v.views.flat_map do |v|
      translate(v.root, summary, inputs, allocation).map { |r| view(r) }
    end
    Value.new(roots, views)
  end

  private def view(root : UInt64) : View
    View.new(root, @uses.size, @guards.dup)
  end

  private def shrink(roots : Array(UInt64), node : Call, chain : String)
    @shrinks << Shrink.new(roots, @uses.size, node, chain, @guards.dup)
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

  private def field_root(root : UInt64, name : String) : UInt64
    # Fold repeated fields onto their ancestor. Recursive calls can walk
    # arbitrarily deep containers; conflating these paths keeps the effect
    # domain finite and conservatively aliases their storage.
    ancestor = root
    while parent = @parents[ancestor]?
      return ancestor if parent[1] == name
      ancestor = parent[0]
    end
    @fields[{root, name}] ||= begin
      id = fresh
      @parents[id] = {root, name}
      id
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
      translate(parent[0], summary, inputs, allocation).map { |r| field_root(r, parent[1]) }
    elsif allocation && summary.result.roots.includes?(root)
      [allocation]
    else
      [] of UInt64
    end
  end

  def initialize(@program : Program, @graph : TapeCallGraph)
  end

  @solving : UInt64?
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
      @graph.effects[target.object_id].shrink =
        Summary.new(seeds, Hash(UInt64, String).new, EMPTY)
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
        @solving = target.object_id
        old = @graph.effects[target.object_id].shrink.not_nil!
        @uses.clear
        @shrinks.clear
        @returns = EMPTY
        @retains.clear
        env = seed_env(target, old.seeds)
        result = merge(value(target.body, env), @returns)
        effects = old.shrinks.dup
        @shrinks.each do |effect|
          effect.roots.each { |root| effects[root] ||= effect.chain }
        end
        # Local allocations cannot be exported as parameter effects.
        effects.reject! { |root, _| translate(root, old, old.seeds.map { |r| Value.new([r], [] of View) }).empty? }
        result = Value.new(result.roots, result.views.map { |v| View.new(v.root, 0) })
        stores = old.stores.dup
        env.slots.each do |root, contents|
          next if translate(root, old, old.seeds.map { |r| Value.new([r], [] of View) }).empty? && !contains_root?(result.roots, root)
          canonical = Value.new(contents.roots, contents.views.map { |v| View.new(v.root, 0) })
          stores[root] = canonical
        end
        updated = Summary.new(old.seeds, effects, merge(old.result, result), stores,
          (old.retains + @retains).uniq)
        if updated != old
          changed = true
          callers[target.object_id]?.try { |ids| dirty.concat(ids) }
          @summary_callers[target.object_id]?.try { |ids| dirty.concat(ids) }
        end
        @graph.effects[target.object_id].shrink = updated
      end
      break unless changed
    end
    @solving = nil
    # Project root paths conservatively onto their parameter. The wire
    # contract may overestimate a field effect, but never loses one.
    @graph.defs.each_value do |target|
      next if target.is_a?(External)
      summary = @graph.effects[target.object_id].shrink.not_nil!
      effect = @graph.effects[target.object_id]
      flags = summary.seeds.map do |seed|
        bits = 0
        bits |= TapeCallGraph::Contract::SHRINK if summary.shrinks.keys.any? { |r| relative_path(r, seed) }
        result_roots = summary.result.roots + summary.result.views.map(&.root)
        # A returned holder may carry the dependency in a nested slot.
        summary.stores.each do |root, contents|
          if contains_root?(summary.result.roots, root)
            result_roots.concat(contents.roots + contents.views.map(&.root))
          end
        end
        bits |= TapeCallGraph::Contract::RESULT if result_roots.any? { |r| relative_path(r, seed) }
        bits |= TapeCallGraph::Contract::RETAIN if summary.retains.any? { |r| relative_path(r, seed) } || summary.stores.values.any? { |v| source_roots(v).any? { |r| relative_path(r, seed) } }
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
      check(target.body, seed_env(target, @graph.effects[target.object_id].shrink.not_nil!.seeds), target) unless TapeRules.unsafe?(@program, target)
    end
    check(node)
    @program.const_initializers.each { |i| check(i.value) }
    @program.class_var_initializers.each { |i| check(i.node) }
  end

  private def root_name(root : UInt64) : String
    if parent = @parents[root]?
      "#{root_name(parent[0])}.#{parent[1]}"
    else
      @root_types[root]?.try(&.to_s) || "tape"
    end
  end

  private def contains_root?(roots : Array(UInt64), root : UInt64) : Bool
    return true if roots.includes?(root)
    if parent = @parents[root]?
      contains_root?(roots, parent[0])
    else
      false
    end
  end

  private def check(body : ASTNode, env = Env.new, owner : Def? = nil)
    @uses.clear
    @shrinks.clear
    @returns = EMPTY
    @checking = true
    @unproved.clear
    @scopes.clear
    @scopes << owner.object_id if owner
    @root_scopes.clear
    @root_births.clear
    live = (env.vars.values + env.slots.values).flat_map(&.roots).to_set
    @root_types.select! { |root, _| live.includes?(root) }
    result = merge(value(body, env), @returns)
    if owner && !{"new", "initialize"}.includes?(owner.name)
      boundary = fresh
      @root_scopes[boundary] = [] of UInt64
      check_store(boundary, stored(result, env), body)
    end
    @checking = false
    @shrinks.each do |shrink|
      @uses.each_with_index do |use, i|
        next if i < shrink.at
        next unless compatible?(shrink.guards, use.guards)
        if live = use.views.find { |view| view.born <= shrink.at && compatible?(view.guards, shrink.guards) && contains_root?(shrink.roots, view.root) }
          shrink.node.raise "cannot shrink tape storage with a live view " \
                            "of #{root_name(live.root)} while shrinking " \
                            "#{shrink.roots.map { |r| root_name(r) }.join(", ")}, " \
                            "used at #{use.node.location} via #{shrink.chain}: copy the view first " \
                            "with copy_to(owner), finish using it before " \
                            "shrinking, or keep an index instead of a view"
        end
      end
    end
    if call = @unproved.first?
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
    name == "String::Builder" || name.starts_with?("Array(") || name.starts_with?("Tre(")
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
          @guards.dup)
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
                         cond : ASTNode? = nil) : Value
    @scopes << body.object_id
    start = @uses.size
    shrink_start = @shrinks.size
    returns = @returns
    entry = loop_env(env, start)
    head = entry
    loop do
      round = head.dup
      value(cond, round) if cond
      value(body, round)
      updated = loop_env(join_env(entry, round), start)
      # Speculative rounds establish the environment, not event order.
      @uses.truncate(0, start)
      @shrinks.truncate(0, shrink_start)
      @returns = returns
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
    result
  end

  private def use(v : Value, node : ASTNode)
    @uses << Use.new(v.views, node, @guards.dup)
  end

  private def proc_type_uncached(type : Type?) : Bool
    return false unless type
    type = type.remove_typedef
    return type.union_types.any? { |member| proc_type?(member) } if type.is_a?(UnionType)
    type.is_a?(ProcInstanceType)
  end

  def value(node : ASTNode, env : Env) : Value
    result = evaluate(node, env)
    if proc_type?(node.type?) && result.procs.empty?
      Value.new(result.roots, result.views, result.procs, true)
    else
      result
    end
  end

  private def evaluate(node : ASTNode, env : Env) : Value
    case node
    when Expressions
      result = EMPTY
      node.expressions.each { |exp| result = value(exp, env) }
      result
    when Var, InstanceVar
      v = env[node.name] ||= if node.is_a?(InstanceVar)
                               Value.new((env["self"]? || EMPTY).roots.map { |r| field_root(r, node.name).as(UInt64) }, [] of View)
                             elsif reference?(node)
                               Value.new([node.object_id], [] of View)
                             else
                               EMPTY
                             end
      v = stored(v, env)
      use(v, node)
      v
    when Assign
      v = value(node.value, env)
      target = node.target
      if target.is_a?(InstanceVar)
        roots = (env["self"]? || EMPTY).roots.map { |r| field_root(r, target.name).as(UInt64) }
        # Fresh growing fields are built into their own slot. A borrowed
        # handle instead keeps the identity of the storage it aliases.
        contents = storage?(node.value) && @graph.fresh?(node.value) ? EMPTY : v
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
      if node.name == "new"
        # Ordinary tape allocations use the caller's tape. A named Owner
        # has its own lexical storage, including each of its field paths.
        @root_scopes[node.object_id] = storage?(node) || {"String", "String::Span"}.includes?(type_name(node.type)) ? [] of UInt64 : @scopes.dup
        @root_types[node.object_id] = node.type
        @root_births[node.object_id] = @uses.size
      end
      receiver = node.obj.try { |obj| value(obj, env) } || env["self"]? || EMPTY
      args = node.args.map { |arg| value(arg, env) }
      named = Hash(String, Value).new
      node.named_args.try &.each do |arg|
        named[arg.name] = v = value(arg.value, env)
        args << v
      end
      node.block_arg.try { |arg| args << value(arg, env) }
      storage_receiver = node.obj.try { |obj| storage?(obj) } ||
                         @graph.targets(node).try &.any? { |target| storage_type?(target.owner) }
      if storage_receiver && SHRINK.includes?(node.name)
        shrink(receiver.roots, node, chain(node.name))
        if node.name == "clear" && receiver.roots.size == 1
          env.slots.reject! do |key, _|
            contains_root?(receiver.roots, key)
          end
        end
      end
      if storage_receiver && {"<<", "push", "[]=", "__loop_store", "unchecked_store"}.includes?(node.name)
        if element = args.last?
          store(receiver.roots.map { |r| field_root(r, "[]").as(UInt64) }, element, env, node, false)
        end
      end
      element_result : Value? = nil
      if node.obj.try { |obj| obj.type?.try { |t| type_name(t).starts_with?("Array(") } } &&
         {"[]", "[]?", "first", "first?", "last", "last?", "fetch", "__loop_fetch"}.includes?(node.name)
        elements = receiver.roots.map { |r| field_root(r, "[]").as(UInt64) }
        if !elements.empty? && elements.all? { |r| env.slots.has_key?(r) }
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
      targets = @graph.targets(node)
      if targets && !targets.empty?
        before_calls = env
        after_calls : Env? = nil
        targets.each do |target|
          summary = @graph.effects[target.object_id]?.try(&.shrink)
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
                if bits & TapeCallGraph::Contract::SHRINK != 0
                  shrink(roots, node, chain("#{node.name} (opaque contract)"))
                end
                if bits & TapeCallGraph::Contract::RETAIN != 0 && !roots.empty?
                  @retains.concat(roots)
                  @unproved << node if @checking
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
              shrink(roots, node, chain("#{node.name} -> #{chain}"))
            end
            retained = summary.retains.flat_map { |r| translate(r, summary, actuals) }
            @retains.concat(retained)
            @unproved << node if @checking && !retained.empty?
            summary.stores.each do |root, contents|
              store(translate(root, summary, actuals, node.object_id),
                translated(contents, summary, actuals, node.object_id), call_env, node)
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
      use(receiver, node)
      args.each { |arg| use(arg, node) }
      derived = receiver
      args.each { |arg| derived = merge(derived, arg) }
      if block = node.block
        outer = env.dup
        yielded_views = derived.views
        if VIEWS.includes?(node.name)
          yielded_views += receiver.roots.map { |root| view(root) }
        end
        yielded = Value.new(derived.roots, yielded_views)
        block.args.each { |arg| outer[arg.name] = yielded }
        @callback_chain << "#{node.name} block"
        @scopes << block.object_id
        if {"tape", "local_tape"}.includes?(node.name)
          value(block.body, outer)
        else
          loop_value(block.body, outer)
        end
        @scopes.pop
        @callback_chain.pop
        use(yielded, block)
        env.keys.each { |key| env[key] = merge(env[key], outer[key]? || EMPTY) }
        env.slots.each_key { |key| env.slots[key] = merge(env.slots[key], outer.slots[key]? || EMPTY) }
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
      if node.name == "new" && type_name(node.type).starts_with?("SlicePool::Run(")
        # A run borrows initialized slots from its Ary argument. Unlike
        # allocating constructors, it must retain that storage's lifetime.
        Value.new([] of UInt64,
          (derived.views + derived.roots.map { |root| view(root) }).uniq)
      elsif {"copy_to", "dup", "to_heap", "new"}.includes?(node.name)
        if reference?(node)
          @root_scopes[node.object_id] = storage?(node) || {"String", "String::Span"}.includes?(type_name(node.type)) ? [] of UInt64 : @scopes.dup
          Value.new([node.object_id], [] of View)
        else
          EMPTY
        end
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
      @guards << {choice, true}
      @scopes << node.then.object_id
      a = value(node.then, left)
      @scopes.pop
      @guards.pop
      @guards << {choice, false}
      @scopes << node.else.object_id
      b = value(node.else, right)
      @scopes.pop
      @guards.pop
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
