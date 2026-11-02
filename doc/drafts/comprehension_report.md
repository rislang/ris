# EGM Stage 6: Comprehension report

Target: doc/drafts/spec-3.5-cycle-roots.md, lines 1..End.

## What this proposes

Rewrites SPEC 3.5. At a call that can lead back into a cycle, the
calling def holds no live owner, growing local, temporary or partial
result (a whole-return call excepted). Growing storage the cycle needs
is owned outside and passed in as a parameter (self counts) that every
back call passes on unchanged; growing it (`@nodes << x`) is legal.
New store rule: inside a cycle a value is stored only where all its
roots are outside it (literals, program data, passed-on parameter);
scratch or a replaced parameter is refused at the store. Direct and
mutual recursion are checked alike.

## How the existing system works, per this document

3.5 bans a live "growing local or parameter"; handles (1.4) make every
growing parameter a reference, so it bans the "pass scratch" it
recommends. 3.5 says nothing of stores; the compiler refuses a literal
store into self's Array under mutual recursion, not direct. Goose §7.8
allows a pool passed by reference and has a cycle store rule.

## Findings

Major:

1. Lines 22-26: "gives the answer both ways" is ambiguous. Say the
   mutual refusal is wrong and both are allowed; say whether direct
   recursion accepts anything it should refuse.
2. Lines 33-36: the passed-on clause is hard to parse. Define a term
   ("a passed-on parameter is one every call back into the cycle passes
   itself, a field or a view of it") and use it.
3. Line 30: "no owner ... is live" may read as banning self. Say an
   owner reached through a parameter is allowed; only one the calling
   def declares is banned.
4. Cycle membership: ris has no `recursive fn`. Say how a cycle is
   found (call graph after specialization, 3.4) and whether the store
   rule covers callees outside it: the example's store is in `node`,
   not a cycle member. Goose's "in the cycle for its whole body" is not
   carried over.
5. "call into a cycle", "back edge", "cycle" are undefined here; add a
   one-line gloss.
6. Lines 81-83: refused cases are prose only; the back-edge case does
   not fit the example (`other` takes only `d`). Give code and the
   expected diagnostic.

Nit:

7. Lines 67-71: `b` unused; note that implicit self is the passed-on
   parameter.
8. Line 30: "callbacks too" is undefined in ris (blocks, procs,
   dispatch?).
9. Line 46: spell out the link: Goose bans by-value nonfixed
   parameters; 1.4 makes every ris growing parameter a handle.
10. Lines 48-49: "not new policy" vs the compiler accepting what it now
    refuses: reconcile.
11. Line 88: "future-work item 5" needs a path or anchor.
12. Lines 90-91: say why the struct question matters to 3.5.
