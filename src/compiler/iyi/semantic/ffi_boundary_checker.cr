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
#
# A def that needs a pointer and calls no C says so, with its reason:
#
#     @[PointerUnsafe("scans the buffer in place")]
#     def scan(...)
#
# Its body may take pointers; `lib` and `fun` stay an @[Ffi] module's. The
# program's manifest may forbid either mark (`forbid ffi, pointer_unsafe`),
# and `ris unsafe` lists every mark with its place, for a review.
module Iyi::FfiBoundaryChecker
  HINT = "Application code uses no pointers; only a module at a C " \
         "library's edge does, marked `@[Ffi]` above its `module` line, " \
         "or a def marked `@[PointerUnsafe(\"reason\")]` (LEARN.md). " \
         "What a speed experiment finds belongs in std."

  def self.check(program : Program, node : ASTNode, filename : String) : Nil
    return unless filename.ris_source?
    return if TapeRules.std?(Location.new(filename, 1, 1))
    return if TapeRules.runtime?(program, Location.new(filename, 1, 1))
    return if std_exercise?(program, filename)
    forbids = own_file?(program, filename) ? program.iyi_forbids : [] of String
    first = node.is_a?(Expressions) ? node.expressions.first? : node
    mark = first.as(ModuleHeader).ffi if first.is_a?(ModuleHeader)
    # A file with no header carries the mark as its first statement.
    mark ||= first if first.is_a?(Annotation) && first.path.names == ["Ffi"]
    if mark
      if forbids.includes?("ffi")
        mark.raise "@[Ffi] in a program whose manifest says `forbid ffi`.\n\n" \
                   "Call C from a package that allows it, or take the " \
                   "`forbid` line out of the manifest."
      end
      return
    end
    node.accept Finder.new(forbids)
  end

  # A file of the program's own package, which its manifest speaks for.
  def self.own_file?(program : Program, filename : String) : Bool
    return false unless package = program.iyi_root_package
    root = File.expand_path(package[1]).gsub('\\', '/').rchop('/')
    File.expand_path(filename).gsub('\\', '/').starts_with?("#{root}/")
  end

  # The def an `@[PointerUnsafe]` stands above, `private` or not.
  def self.marked_def?(node : ASTNode) : Bool
    node = node.exp if node.is_a?(VisibilityModifier)
    node.is_a?(Def)
  end

  def self.check_pointer_unsafe(ann : Annotation, forbids : Array(String)) : Nil
    if forbids.includes?("pointer_unsafe")
      ann.raise "@[PointerUnsafe] in a program whose manifest says " \
                "`forbid pointer_unsafe`.\n\n" \
                "Read bytes with `s[i]`, `s[a, n]` or `s.byte_at(i)`, or take " \
                "the `forbid` line out of the manifest."
    end
    reason = ann.args.first?
    unless ann.args.size == 1 && ann.named_args.nil? &&
           reason.is_a?(StringLiteral) && !reason.value.blank?
      ann.raise "@[PointerUnsafe] takes the reason the def needs a " \
                "pointer, as `@[PointerUnsafe(\"scans the buffer in place\")]`."
    end
  end

  # ris's own `bench/`, beside `src/`: std's exercises and probes, which
  # test std's insides as std's own code would, not a program's. A bench
  # script writes its probes under `bench/.work/` for this, not in /tmp.
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
      "`pointerof` outside an @[Ffi] module or @[PointerUnsafe] def.\n\n" \
      "Index a `UInt8[N]` buffer directly (`buf[i]`) to read it back; a C " \
      "call that fills one belongs in an @[Ffi] module."
    when Path
      return unless node.names == ["Pointer"]
      "`Pointer` outside an @[Ffi] module or @[PointerUnsafe] def.\n\n" \
      "Hold bytes in a String (`s[i]`, `s[a, n]`, `s.byte_at(i)`), a " \
      "`UInt8[N]`, an `Array(UInt8)` or a `Str`."
    when LibDef
      "a `lib` block outside an @[Ffi] module: calling C is the boundary.\n\n" \
      "Put the binding in a module of its own, mark it `@[Ffi]`, and give " \
      "the rest of the program an API without pointers."
    when FunDef
      "a `fun` outside an @[Ffi] module: calling C is the boundary.\n\n" \
      "Put it in a module of its own, marked `@[Ffi]`."
    when Call
      if node.name == "to_unsafe"
        "`to_unsafe` outside an @[Ffi] module or @[PointerUnsafe] def.\n\n" \
        "Read a byte with `s.byte_at(i)` (UInt8) or `s[i]` (Char), and write " \
        "part of a string with `io << s[a, n]`, not `io.write(ptr + a, n)`."
      elsif node.name == "new" && node.block && node.args.size == 1 &&
            (obj = node.obj).is_a?(Path) && obj.names == ["String"]
        "`String.new(capacity) { |pointer| … }` outside an @[Ffi] module " \
        "or @[PointerUnsafe] def: " \
        "it yields a raw pointer.\n\n" \
        "Build it with `String.build(capacity) { |io| io.write_byte(b) }`."
      end
    end
  end

  class Finder < Visitor
    def initialize(@forbids : Array(String))
    end

    # An `@[PointerUnsafe]` lets the def under it through: the parser
    # leaves an annotation beside the node it marks.
    def visit(node : Expressions)
      marked : Annotation? = nil
      node.expressions.each do |exp|
        if exp.is_a?(Annotation) && exp.path.names == ["PointerUnsafe"]
          FfiBoundaryChecker.check_pointer_unsafe(exp, @forbids)
          marked = exp
          next
        end
        if marked && !exp.is_a?(Annotation)
          unless FfiBoundaryChecker.marked_def?(exp)
            marked.raise "@[PointerUnsafe] marks a def: the one whose " \
                         "body takes the pointer."
          end
          marked = nil
          next
        end
        exp.accept self
      end
      marked.try &.raise "@[PointerUnsafe] marks a def: the one whose " \
                         "body takes the pointer."
      false
    end

    def visit(node : ASTNode)
      if reason = FfiBoundaryChecker.refusal(node)
        node.raise "#{reason}\n\n#{HINT}"
      end
      true
    end
  end
end
