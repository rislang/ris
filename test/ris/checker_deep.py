#!/usr/bin/env python3
"""Write a program nested as deep as the parser reads (126 levels under a
def) in three shapes: ifs, calls and operators. check.sh's checker_deep
gate checks it under a reduced stack."""
import sys
n = 126
out = ["def id(text : String) : String", "  text", "end", "",
       "def pick(n : Int32, text : String) : String"]
out += [" " * (i + 1) + f"if n > {i}" for i in range(n)]
out.append(" " * (n + 1) + "text")
for i in reversed(range(n)):
    out += [" " * (i + 1) + "else", " " * (i + 2) + "text", " " * (i + 1) + "end"]
out += ["end", "", "def call(text : String) : String",
        "  " + "id(" * n + "text" + ")" * n, "end", "",
        "def sum(n : Int32) : Int32", "  " + "(" * n + "n" + " + 1)" * n, "end",
        'puts pick(3, "x"), call("y"), sum(1)']
open(sys.argv[1], "w").write("\n".join(out) + "\n")
