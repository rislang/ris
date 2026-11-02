#!/usr/bin/env python3
"""Print each def of scope_round_marks.ri with the wrong scope mark in its
release IR. Only a kept mark can reach __iyi_scope_release. yield_loop is
inlined into the program, so it is not checked here."""
import re
import sys

ir = open(sys.argv[1]).read()
EXPECT = {"byte_scan": False, "block_scan": False, "builder_loop": True,
          "proc_loop": True}
for name, kept in EXPECT.items():
    found = re.search(r'^define [^\n]*@"\*' + name + r"[^\n]*\{\n(.*?)^\}",
                      ir, re.M | re.S)
    if not found:
        print(f"{name}: not in the IR")
    elif ("__iyi_scope_release" in found.group(1)) != kept:
        print(f"{name}: expected a kept mark: {kept}")
