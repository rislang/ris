# ris: `ris unsafe` — every place the program steps past its safety rules,
# for a review: `@[Ffi]` modules, `@[PointerUnsafe]` defs with their
# reasons and `@[TapeUnsafe]` defs, under the current directory or the
# directories given, and what the manifest there forbids. Read from the
# parsed source, so it answers for code that does not type-check yet.
require "../mod/installer"

class Iyi::Command
  private def unsafe
    if options.first?.in?("--help", "-h")
      puts <<-USAGE
        Usage: #{Command.program_name} unsafe [directory...]

        List every mark that lifts a safety rule, one per line as
        `file:line: mark`: @[Ffi] modules, @[PointerUnsafe] defs with
        their reasons, and @[TapeUnsafe] defs. The source is every .ri
        and .iyi file under each directory (default: the current one),
        except hidden directories and lib/. A manifest's `forbid` line
        is printed first. Exit 0 whatever is found.
        USAGE
      exit
    end

    dirs = options.empty? ? ["."] : options.dup
    dirs.each do |dir|
      manifest = Mod::Installer.manifest_in(dir)
      if File.file?(manifest)
        forbids = Mod::ModFile.parse(File.read(manifest), manifest).forbids
        puts "#{manifest}: forbid #{forbids.join(", ")}" unless forbids.empty?
      end
      unsafe_sources(dir).each do |file|
        nodes = Parser.new(File.read(file)).tap(&.filename=(file)).parse
        unsafe_marks(nodes) do |ann, what|
          puts "#{file}:#{ann.location.try(&.line_number) || 1}: #{what}"
        end
      rescue CodeError | IO::Error
        STDERR.puts "#{file}: does not parse, not listed"
      end
    end
  rescue ex : Mod::ModError
    abort! ex.message.to_s, :USAGE_ERROR
  end

  private def unsafe_sources(dir : String) : Array(String)
    found = [] of String
    return [dir] if dir.ris_source? && File.file?(dir)
    Dir.each_child(dir) do |entry|
      full = File.join(dir, entry)
      if File.info?(full, follow_symlinks: false).try(&.directory?)
        next if entry.starts_with?('.') || entry == "lib"
        found.concat(unsafe_sources(full))
      elsif entry.ris_source?
        found << full
      end
    end
    found.sort!
  end

  private def unsafe_marks(node : ASTNode, &block : Annotation, String ->) : Nil
    case node
    when ModuleHeader
      node.ffi.try { |ann| block.call(ann, "@[Ffi]") }
    when Annotation
      case node.path.names
      when ["Ffi"], ["TapeUnsafe"]
        block.call(node, "@[#{node.path.names.first}]")
      when ["PointerUnsafe"]
        reason = node.args.first?
        reason = reason.value if reason.is_a?(StringLiteral)
        block.call(node, "@[PointerUnsafe] #{reason}")
      end
    when Expressions
      node.expressions.each { |exp| unsafe_marks(exp, &block) }
    when ModuleDef, ClassDef
      unsafe_marks(node.body, &block)
    end
  end
end
