#!/usr/bin/env python3
"""Growing text across a module artifact: a String local and field that
get `<<`, and an Array field appended in a chain, built from source and
from the .iyimod give the same output. The artifact's bodies are already
lowered: lowering them again took `__temp_1 << item` for growing text."""
import os
from pathlib import Path
import subprocess
import tempfile

RIS = Path(os.environ.get("RIS", "./bin/ris")).resolve()
EXPECTED = "one.two.\nx-y\n2\nmain!\n"

with tempfile.TemporaryDirectory(prefix="ris-iyimod-text-") as directory:
    work = Path(directory)
    (work / "app").mkdir()
    library = work / "app/text.ri"
    library.write_text('''module app/text
pub class Collector
  getter text : String
  def initialize
    @text = ""
  end
  def add(x : String) : Nil
    @text << x << "."
    nil
  end
end
pub class Stack(T)
  @items : Array(T) = [] of T
  def initialize
  end
  def push(item : T) : Int32
    @items << item << item
    @items.size
  end
end
pub def joined(a : String, b : String) : String
  s = ""
  s << a << "-"
  s << b
  s
end
''')
    main = work / "main.ri"
    main.write_text('''module main
import app/text
tape do
  c = App::Text::Collector.new
  c.add("one")
  c.add("two")
  puts c.text
  puts App::Text.joined("x", "y")
  stack = App::Text::Stack(Int32).new
  puts stack.push(5)
  s = ""
  s << "main" << "!"
  puts s
end
''')

    def build(option, executable):
        subprocess.run([str(RIS), "build", option, "mods", "-o", executable,
                        str(main)], cwd=work, check=True)

    build("--emit-iyimod", "source")
    source = subprocess.check_output([str(work / "source")], text=True)
    library.unlink()
    build("--use-iyimod", "artifact")
    artifact = subprocess.check_output([str(work / "artifact")], text=True)
    assert source == artifact == EXPECTED, (source, artifact)
    print("runs     iyimod_text_growth (source and artifact match)")

    # An Array field appended in an iyi module: the artifact's lowered
    # `__temp_N << item` met the consumer's own `__temp_N`.
    (work / "app/stack.iyi").write_text('''module app/stack

pub class Stack(T)
  @items : Array(T) = [] of T

  def initialize
  end

  def push(item : T) : Int32
    @items << item
    @items.size
  end
end
''')
    main = work / "main.iyi"
    main.write_text("module main\n\nimport app/stack::*\n\n"
                    "stack = Stack(Int32).new\nputs stack.push(5)\n")
    build("--emit-iyimod", "source")
    source = subprocess.check_output([str(work / "source")], text=True)
    (work / "app/stack.iyi").unlink()
    build("--use-iyimod", "artifact")
    artifact = subprocess.check_output([str(work / "artifact")], text=True)
    assert source == artifact == "1\n", (source, artifact)
    print("runs     iyimod_text_growth (iyi Array field from its artifact)")

    # Three artifact contracts (2026-10-30): std/int's `self << n` stays
    # Int's shift (it was lowered as text growth, "can't change the value
    # of self"); an impl method carries its checked contract, not the
    # opaque default; an imported constructor that fills its Array fields
    # does not count as shrinking a value someone views.
    (work / "app/kit.iyi").write_text('''module app/kit

import std/int

@[OnTape]
pub struct KitError
  getter message : String

  def initialize(@message : String)
  end
end

impl Error for KitError
  def message : String
    @message
  end
end

@[OnTape]
pub struct Bag
  @items : Array(Int32)

  def initialize(from : Array(Int32))
    @items = [0]
    from.each { |n| @items << n }
  end

  def size : Int32
    @items.size
  end
end

pub def check(text : String) : KitError | Int32
  text.size > 3 ? KitError.new(text) : text.size
end
''')
    main.write_text('''module main

import app/kit::*
import std/int

def size_of(text : String) : Int32
  v = check(text)
  raise "#{text.inspect} refused with #{v.message.inspect}" if v.is_a?(KitError)
  v
end

x = 1_i128
puts x >> -3
v = check("long#{1}")
puts "refused with #{v.message.inspect}" if v.is_a?(KitError)
puts size_of("ab")
puts Bag.new([1, 2, 3]).size
''')
    build("--emit-iyimod", "source")
    source = subprocess.check_output([str(work / "source")], text=True)
    (work / "app/kit.iyi").unlink()
    build("--use-iyimod", "artifact")
    artifact = subprocess.check_output([str(work / "artifact")], text=True)
    expected = '8\nrefused with "long1"\n2\n4\n'
    assert source == artifact == expected, (source, artifact)
    print("runs     iyimod_text_growth (self shift, impl and constructor "
          "contracts from the artifact)")
