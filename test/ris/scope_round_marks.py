#!/usr/bin/env python3
"""Print each def of scope_round_marks.ri with the wrong scope mark in its
release IR. Only a kept mark can reach __iyi_scope_release. yield_loop is
inlined into the program, so it is not checked here. wide_kind calls no
Array#[]. A second file, the unoptimised IR, has Array#[] and String#[]
marked always inline, and a loop's `next` reset only where text may have
been made since the round's mark."""
import re
import sys

ir = open(sys.argv[1]).read()
EXPECT = {"byte_scan": False, "block_scan": False, "builder_loop": True,
          "proc_loop": True, "escape_loop": True}
for name, kept in EXPECT.items():
    found = re.search(r'^define [^\n]*@"\*' + name + r"[^\n]*\{\n(.*?)^\}",
                      ir, re.M | re.S)
    if not found:
        print(f"{name}: not in the IR")
    elif ("__iyi_scope_release" in found.group(1)) != kept:
        print(f"{name}: expected a kept mark: {kept}")

def body(text, name):
    found = re.search(r'^define [^\n]*@"\*' + name + r"[^\n]*\{\n(.*?)^\}",
                      text, re.M | re.S)
    return found.group(1) if found else ""

wide = body(ir, "wide_kind")
if not wide or re.search(r'call [^\n]*#\[\]', wide):
    print("wide_kind: Array#[] is not inlined")

# In the unoptimised IR (the second file), `[]` on an Array and a String
# is marked always inline: htmlparse's 340 reads of a 56-byte node were
# each a call that copied the whole node, which LLVM judged too dear to
# inline, though one caller here shows it inlined either way.
if len(sys.argv) > 2:
    debug = open(sys.argv[2]).read()
    groups = dict(re.findall(r"^attributes (#\d+) = \{([^}]*)\}", debug,
                             re.M))
    for name in ("Array(Wide)@Array(T)#[]<Int32>:Wide",
                 "String#[]<Int32>:UInt8"):
        found = re.search(r'^define [^\n]*@"\*' + re.escape(name)
                          + r'"[^\n]*?(#\d+)', debug, re.M)
        if not found or "alwaysinline" not in groups.get(found.group(1), ""):
            print(f"{name}: not marked always inline")
    # Each reset is a call there: escape_loop's `next` has none, only its
    # round's end; next_loop's `next` follows text made, and keeps one.
    for name, count in (("escape_loop", 1), ("next_loop", 2)):
        resets = body(debug, name).count("__iyi_scope_reset")
        if resets != count:
            print(f"{name}: expected {count} resets, found {resets}")
