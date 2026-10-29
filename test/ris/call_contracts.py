#!/usr/bin/env python3
"""Focused call-contract gates, including real bodyless module imports."""
import hashlib
import os
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RIS = Path(os.environ.get("RIS", ROOT / "bin/ris")).resolve()


def build(path, *options, refused=None):
    result = subprocess.run(
        [str(RIS), "build", "--no-codegen", *map(str, options), str(path)],
        cwd=path.parent, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if refused:
        assert result.returncode and refused in result.stdout, result.stdout
    else:
        assert result.returncode == 0, result.stdout
    return result.stdout


# This removes one optional signature field's contents, preserving the
# container and every other section. It models a writer without a summary.
def without_contract(data, contract):
    data = bytearray(data)
    count = struct.unpack_from("<I", data, 12)[0]
    start = 16 + count * 16
    for index in range(count):
        entry = 16 + index * 16
        kind, _, size = struct.unpack_from("<HHI", data, entry)
        if kind == 4:  # Exports
            encoded = contract.encode()
            needle = struct.pack("<I", len(encoded)) + encoded
            offset = data.index(needle, start, start + size)
            data[offset:offset + len(needle)] = struct.pack("<I", 0)
            size -= len(encoded)
            struct.pack_into("<I", data, entry + 4, size)
            checksum = int.from_bytes(
                hashlib.md5(data[start:start + size]).digest()[:8], "big")
            struct.pack_into("<Q", data, entry + 8, checksum)
            return data
        start += size
    raise AssertionError("module has no Exports section")


with tempfile.TemporaryDirectory(prefix="ris-call-contracts-") as directory:
    work = Path(directory)
    (work / "app").mkdir()
    library = work / "app/effects.ri"
    library.write_text("""module app/effects
pub def clear(bytes : String::Builder) : Nil
  bytes.clear
  nil
end
pub def view(bytes : String::Builder, ignored : Int32 = 0) : String
  bytes.finish
end
pub def pause(bytes : String::Builder) : Nil
  sleep 1
  nil
end
private def seed : Int32
  41
end
pub struct Counter
  @@base : Int32 = seed + 1
  def self.value : Int32
    @@base
  end
end
""")
    main = work / "main.ri"

    def program(body):
        main.write_text("module main\nimport app/effects\n"
                        "def exercise\n"
                        "  b = String::Builder.new\n  b << \"abc\"\n"
                        + body + "\nend\ntape { exercise }\n"
                        "puts App::Effects::Counter.value\n")

    program("  App::Effects.clear(b)\n  puts App::Effects.view(b)"
            "\n  App::Effects.pause(b)")
    mods = work / "mods"
    build(main, "--emit-iyimod", mods)
    library.unlink()
    build(main, "--use-iyimod", mods)
    print("accepts  imported checked contract (source removed)")

    program("  v = b.finish\n  App::Effects.pause(b)\n  puts v")
    build(main, "--use-iyimod", mods)
    print("accepts  imported suspension contract with live view")

    program("  v = b.finish\n  App::Effects.clear(b)\n  puts v")
    build(main, "--use-iyimod", mods,
          refused="cannot shrink tape storage with a live view")
    print("refused  imported shrink contract")

    program("  v = App::Effects.view(b)\n  b.clear\n  puts v")
    build(main, "--use-iyimod", mods,
          refused="cannot shrink tape storage with a live view")
    print("refused  imported result-view contract")

    artifact = mods / "app/effects.iyimod"
    original = artifact.read_bytes()
    artifact.write_bytes(without_contract(original, "2;0;0;0,1"))
    build(main, "--use-iyimod", mods,
          refused="imported def lacks a checked tape contract")
    print("refused  imported def without checked contract")

for name, message in [
    ("contract_opaque_proc", "cannot shrink tape storage with a live view"),
    ("contract_opaque_retain", "cannot prove opaque callback retain/escape"),
    ("contract_mixed_proc", "cannot shrink tape storage with a live view"),
]:
    build(ROOT / "test/ris/refused" / (name + ".ri"), refused=message)
    print("refused  " + name)

result = subprocess.run(
    [str(RIS), "run", str(ROOT / "test/ris/contract_spawn.ri")],
    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
)
assert result.returncode == 0 and result.stdout.strip() == "abc", result.stdout
print("accepts  task reading a view in a group joined inside the tape")

result = subprocess.run(
    [str(RIS), "run", str(ROOT / "test/ris/contract_suspend.ri")],
    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
)
assert result.returncode == 0 and result.stdout.strip() == "abc", result.stdout
print("accepts  suspending call with live view in one fiber")

result = subprocess.run(
    [str(RIS), "run", str(ROOT / "test/ris/contract_known_proc.ri")],
    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
)
assert result.returncode == 0 and result.stdout.strip() == "3", result.stdout
print("accepts  directly known callback with tape argument")

# Runtime proc dispatch must not make ordinary tape construction suspend.
# An opaque callback's handle is not itself a borrowed tape argument.
with tempfile.TemporaryDirectory(prefix="ris-call-defaults-") as directory:
    main = Path(directory) / "main.ri"
    main.write_text('''TEXT = "value #{42}"
WORDS = Array(String){"one", "two"}
class Greeter
  def initialize(@hello : Proc(Bool)?)
  end
  def greet
    if hello = @hello
      hello.call
    end
  end
end
Greeter.new(-> { true }).greet
class Counter
  def initialize(@value : Int32)
  end
  def visit(callback : Proc(Int32, Nil))
    callback.call(@value)
  end
end
Counter.new(42).visit(->(value : Int32) { puts value })
puts TEXT, WORDS[0]
''')
    build(main)
    print("accepts  program construction and non-tape callback inputs")

    main.write_text('''def initial : String
  sleep 0
  String.new("bad")
end
TEXT = initial
puts TEXT
''')
    build(main, refused="program tape initializers cannot suspend")
    print("refused  suspending program initializer")
