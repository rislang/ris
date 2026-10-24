# ris: raw pointers live only at a C library's edge. `Pointer`, `T*`,
# `pointerof`, `to_unsafe`, `String.new(capacity) { |pointer| }`, `lib`
# blocks and `fun` are refused in a ris source file unless its header is
# marked, or, in a file with none, its first statement is the mark:
#
#     @[Ffi]
#     module app/sqlite
#
# An agent follows compiler errors, not prose, so each error names the
# safe form that replaces the pointer, and the mark only for calling C.
# std (`/std/`) and the runtime (`src/iyi/`, `.cr`) are exempt, as they are
# from the tape's rules (`TapeRules`), and so are std's exercises in ris's
# own `bench/`: speed is std's to give, through the tape, not a pointer's.
# Checked on the parsed source, so a def nothing calls is held to it too.
# `--allow-unsafe` lifts the check for one build, for an experiment.
module Iyi::FfiBoundaryChecker
  HINT = "Application code uses no pointers; only a module at a C " \
         "library's edge does, marked `@[Ffi]` above its `module` line " \
         "(LEARN.md). A speed experiment, never committed, may build " \
         "with `--allow-unsafe`; what it finds belongs in std."

  def self.check(program : Program, node : ASTNode, filename : String) : Nil
    return unless filename.ris_source?
    return if program.compiler.try(&.allow_unsafe?)
    return if TapeRules.std?(Location.new(filename, 1, 1))
    return if TapeRules.runtime?(program, Location.new(filename, 1, 1))
    return if std_exercise?(program, filename)
    first = node.is_a?(Expressions) ? node.expressions.first? : node
    return if first.is_a?(ModuleHeader) && first.ffi?
    # A file with no header carries the mark as its first statement.
    return if first.is_a?(Annotation) && first.path.names == ["Ffi"]
    node.accept Finder.new
  end

  # ris's own `bench/`, beside `src/`: std's exercises and probes, which
  # test std's insides as std's own code would, not a program's.
  def self.std_exercise?(program : Program, filename : String) : Bool
    file = File.expand_path(filename).gsub('\\', '/')
    program.iyi_path.entries.any? do |entry|
      next false unless File.directory?(File.join(entry, "std"))
      root = File.dirname(File.expand_path(entry)).gsub('\\', '/')
      file.starts_with?("#{root}/bench/")
    end
  end

  def self.refusal(node : ASTNode) : String?
    case node
    when PointerOf
      "`pointerof` outside an @[Ffi] module.\n\n" \
      "Index a `UInt8[N]` buffer directly (`buf[i]`) to read it back; a C " \
      "call that fills one belongs in an @[Ffi] module."
    when Path
      return unless node.names == ["Pointer"]
      "`Pointer` outside an @[Ffi] module.\n\n" \
      "Hold bytes in a String (`s[i]`, `s[a, n]`, `s.byte_at(i)`), a " \
      "`UInt8[N]`, an `Array(UInt8)` or a `Tape::String`."
    when LibDef
      "a `lib` block outside an @[Ffi] module: calling C is the boundary.\n\n" \
      "Put the binding in a module of its own, mark it `@[Ffi]`, and give " \
      "the rest of the program an API without pointers."
    when FunDef
      "a `fun` outside an @[Ffi] module: calling C is the boundary.\n\n" \
      "Put it in a module of its own, marked `@[Ffi]`."
    when Call
      if node.name == "to_unsafe"
        "`to_unsafe` outside an @[Ffi] module.\n\n" \
        "Read a byte with `s.byte_at(i)` (UInt8) or `s[i]` (Char), and write " \
        "part of a string with `io << s[a, n]`, not `io.write(ptr + a, n)`."
      elsif node.name == "new" && node.block && node.args.size == 1 &&
            (obj = node.obj).is_a?(Path) && obj.names == ["String"]
        "`String.new(capacity) { |pointer| … }` outside an @[Ffi] module: " \
        "it yields a raw pointer.\n\n" \
        "Build it with `String.build(capacity) { |io| io.write_byte(b) }`."
      end
    end
  end

  class Finder < Visitor
    def visit(node : ASTNode)
      if reason = FfiBoundaryChecker.refusal(node)
        node.raise "#{reason}\n\n#{HINT}"
      end
      true
    end
  end
end
