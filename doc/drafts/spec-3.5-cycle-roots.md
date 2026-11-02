# Draft: SPEC 3.5, what a cycle may hold and store

Status: draft, revised after EGM review (2026-11-02). Not yet in
SPEC.md.

## Problem

SPEC 3.5 now reads:

> 3.5 Recursion (Goose §7.8): no owner, growing local or parameter,
> temporary, or result under construction outside its caller's
> destination is live at a call into a cycle (callbacks too): pass
> scratch. A call that is a return's whole value builds in the caller's
> destination (1.5) and is allowed.

Array, RisTree and builders are handles (1.4), so every growing
parameter is a reference. Read literally, 3.5 bans a cycle that grows
a field of an owner it was handed (`@nodes << x` in a recursive
parser), and also tells the reader to "pass scratch", which is such a
parameter. Goose §7.8 allows it: a pool handed to the cycle by
reference may be grown by every activation.

3.5 says nothing about what a cycle may store. The compiler refuses a
literal stored into self's Array under mutual recursion
(`pipe -> other -> pipe`) and accepts it under direct recursion
(`pipe -> pipe`). The mutual refusal is a compiler bug against 3.2 and
3.6: the literal's root outlives every destination. Both forms are
allowed; this draft states why.

## Proposed text

> 3.5 Recursion (Goose §7.8): at a call into a cycle, no owner the
> calling def declares, growing local, temporary, or result under
> construction outside its caller's destination is live: pass scratch
> in. Growing storage a cycle uses comes from a passed-on parameter: a
> parameter, self included, that every call back into the cycle passes
> as itself or a field or view of it; a back edge that passes other
> growing storage is refused at the call. A call that is a return's
> whole value builds in the caller's destination (1.5) and is allowed.
>
> 3.7 Cycle stores (Goose §7.8): a value made or passed in a cycle is
> stored only where every root it has is outside the cycle: a literal,
> program data, a passed-on parameter, or a local of an enclosing def
> outside the cycle that a block captures. A value rooted in a cycle
> def's scratch, or in a parameter to which a back edge passes other
> storage, is refused at the store, naming the safe forms: pass the
> storage in, or copy_to(owner).

Terms, for both rules: a cycle is a set of defs that call each other,
found on the call graph after specialization (3.4); a call into a
cycle is any call that can lead back to the caller, through blocks and
dispatch too; a back edge is such a call made inside the cycle. A def
is in the cycle for its whole body, and a store made by a def the cycle
calls is checked by its roots like one made in the cycle.

## Decisions

* Growing storage: refused at the call, as in Goose's pool rule (a back
  edge swapping pools is an error). Other values: refused at the store
  that relies on them, as in Goose's parameter rule.
* A parameter to which a back edge passes other storage stays refused,
  even where every activation's store would be safe; per-activation
  checking is Goose's future work (its TODO, "Cycle store rule
  refinement") and is not adopted.
* Goose's second-tier roots (a parameter whose argument is always read
  through a passed-on parameter or pool, `rest(c, c.nodes.push(...))`)
  are not adopted yet; such a store is refused.
* No `recursive` annotation: ris finds cycles on the call graph.
* "Owner" is what 2.1 says: a class with a growing field. The rules say
  nothing new about structs; self in the examples is a class instance.
* Rejected: only narrowing 3.5 and leaving stores to 3.2 and 3.6. Depth
  checks cannot tell two activations of one def apart (Goose §7.8), so
  3.2 alone cannot decide the second refused example below.
* Goose bans a by-value growing parameter; ris has none, since 1.4 makes
  every Array, RisTree and builder parameter a handle and String is
  read-only, so these rules admit nothing Goose bans.

## Examples

Allowed, mutual recursion; direct recursion is checked the same way.
The implicit self is the passed-on parameter:

```crystal
class P
  def initialize
    @nodes = Array(String).new(8)
  end

  def node(a : String) : Int32
    @nodes << a
    @nodes.size - 1
  end

  def pipe(d : Int32) : Int32
    return 0 if d > 3
    other(d + 1)
    node("x")
  end

  def other(d : Int32) : Int32
    pipe(d)
  end
end
p = P.new
puts p.pipe(0)
```

Refused at the store (3.7): the entry passes a literal, a back edge
passes text built in the calling activation's scratch. Each activation
stores a view into a text that dies with the activation before it.

```crystal
  def walk(t : String, d : Int32) : Int32
    @nodes << t                  # refused: t may be a back edge's scratch
    return 0 if d > 3
    s = "#{t}/#{d}"
    walk(s, d + 1)
  end
  # caller: p.walk("root", 0)
```

Refused at the call (3.5): a back edge passes other growing storage.

```crystal
  def fill(out : Array(String), d : Int32) : Int32
    out << "x"
    return 0 if d > 3
    fill(@other, d + 1)          # refused: out must be passed on
  end
```

## Risks

* Code that swaps growing storage at a back edge, or stores a value a
  back edge replaces, must be rewritten: pass one storage down, or
  copy_to(owner).
* The diagnostic for a scratch value moves from the call to the store;
  messages name the store and the back edge.
