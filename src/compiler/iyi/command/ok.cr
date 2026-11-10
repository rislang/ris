# ris: `ris ok` — one verb that says whether the work is done.
#
# It runs the verbs a finished change must pass, fastest first: `fmt
# --check`, `mod tidy --check` (when there is a manifest), `check`, `vet`
# and `test`. It stops at the first that fails, shows that verb's own
# output, and names the command that fixes it. Exit 0 means every step
# passed, so neither a person nor an agent has five commands to remember.
#
# Each step runs this same binary with the verb's own arguments, as `ris
# mcp` does: every verb ends in `exit`, so running one in this process
# would end the run at the first step. The verdicts are the verbs', with
# no second implementation of any of them.
require "json"

class Iyi::Command
  OK_STEP_WIDTH = 7

  private record OkStep, name : String, runs : Array(Array(String)),
    next_hint : String

  private def ok
    json = false
    affected = [] of String
    paths = [] of String
    while option = options.shift?
      case option
      when "--help", "-h"
        puts ok_usage
        exit
      when "--json"
        json = true
      when "--affected"
        value = options.shift?.presence
        abort! "--affected takes a changed file", :USAGE_ERROR unless value
        affected << value
      when .starts_with?('-')
        abort! "ok: unknown flag #{option}. `#{Command.program_name} ok --help` lists them", :USAGE_ERROR
      else
        abort! "ok: no such file or directory: #{option}", :USAGE_ERROR unless File.exists?(option)
        paths << option
      end
    end

    name = Command.program_name
    steps = ok_steps(name, paths, affected)
    exe = Process.executable_path.not_nil!
    results = [] of {String, String}
    failed = nil
    output = ""

    steps.each do |step|
      if step.runs.empty?
        results << {step.name, "skip"}
        puts ok_line(step.name, "skip (nothing to #{step.name})") unless json
        next
      end
      buffer = IO::Memory.new
      passed = step.runs.all? do |args|
        Process.run(exe, args, output: buffer, error: buffer).success?
      end
      results << {step.name, passed ? "ok" : "fail"}
      puts ok_line(step.name, passed ? "ok" : "FAIL") unless json
      unless passed
        failed = step
        output = buffer.to_s
        break
      end
    end

    if json
      JSON.build(STDOUT) do |builder|
        builder.object do
          builder.field "ok", failed.nil?
          builder.field "steps" do
            builder.array do
              results.each do |step_name, status|
                builder.object do
                  builder.field "name", step_name
                  builder.field "status", status
                end
              end
            end
          end
          builder.field "failed", failed.try(&.name)
          builder.field "output", failed ? output : nil
          builder.field "next", failed.try(&.next_hint)
        end
      end
      puts
    elsif failed
      puts
      print output
      puts unless output.empty? || output.ends_with?('\n')
      puts
      puts "next: #{failed.next_hint}"
    end
    exit(failed ? 1 : 0)
  end

  private def ok_line(name : String, status : String) : String
    "#{name.ljust(OK_STEP_WIDTH)}#{status}"
  end

  private def ok_steps(name : String, paths : Array(String),
                       affected : Array(String)) : Array(OkStep)
    again = "then run #{name} ok again"
    # `fmt` given a directory reads only .cr files, so the .ri files are
    # listed for it.
    sources = ok_sources(paths)
    targets = ok_targets(paths)
    affected_flags = affected.flat_map { |file| ["--affected", file] }

    steps = [] of OkStep
    fmt_runs = sources.empty? ? [] of Array(String) : [["fmt", "--check"] + sources]
    shown = paths.empty? ? sources : paths
    steps << OkStep.new("fmt", fmt_runs,
      "#{name} fmt #{shown.join(" ")}, #{again}")
    # `mod tidy` reads the current directory's manifest, so it runs when
    # the project is the current directory.
    if paths.empty? && {"ris.mod", "iyi.mod"}.any? { |m| File.file?(m) }
      steps << OkStep.new("tidy", [["mod", "tidy", "--check"]],
        "#{name} mod tidy, #{again}")
    end
    check_runs =
      if affected.empty?
        targets.map { |file| ["check", file] }
      else
        [["check"] + affected_flags]
      end
    fix_file = affected.first? || targets.first? || "FILE"
    steps << OkStep.new("check", check_runs,
      "#{name} fix #{fix_file} (applies the compiler's edits; " \
      "fix the rest by hand), #{again}")
    steps << OkStep.new("vet", targets.map { |file| ["vet", file] },
      "use or remove the unreachable methods named above, #{again}")
    has_tests = sources.any?(&.ends_with?("_test.ri"))
    test_runs = has_tests ? [["test"] + affected_flags + paths] : [] of Array(String)
    steps << OkStep.new("test", test_runs,
      "fix the failing test, #{again}")
    steps
  end

  # Every .ri file the PATHs hold (the current directory when none is
  # given), hidden directories and `lib` left out.
  private def ok_sources(paths : Array(String)) : Array(String)
    files = [] of String
    (paths.empty? ? ["."] : paths).each do |path|
      if File.file?(path)
        files << path if path.ends_with?(".ri")
      elsif Dir.exists?(path)
        ok_walk(path, files)
      end
    end
    files
  end

  private def ok_walk(dir : String, files : Array(String)) : Nil
    Dir.children(dir).sort!.each do |child|
      next if child.starts_with?('.')
      path = dir == "." ? child : File.join(dir, child)
      if Dir.exists?(path)
        ok_walk(path, files) unless child == "lib"
      elsif child.ends_with?(".ri")
        files << path
      end
    end
  end

  # The program files `check` and `vet` compile: each given .ri file, and
  # for each directory (the current one when none is given) its root
  # module named by the manifest, else every non-test .ri file in it.
  private def ok_targets(paths : Array(String)) : Array(String)
    dirs = paths.empty? ? ["."] : paths.select { |path| Dir.exists?(path) }
    files = paths.select { |path| File.file?(path) && !path.ends_with?("_test.ri") }
    dirs.each do |dir|
      if root = ok_root_module(dir)
        files << root
      else
        Dir.children(dir).sort!.each do |child|
          next unless child.ends_with?(".ri") && !child.ends_with?("_test.ri")
          files << (dir == "." ? child : File.join(dir, child))
        end
      end
    end
    files
  end

  private def ok_root_module(dir : String) : String?
    manifest = {"ris.mod", "iyi.mod"}.map { |m| File.join(dir, m) }.find { |m| File.file?(m) }
    return nil unless manifest
    File.each_line(manifest) do |line|
      if match = line.match(/^\s*module\s+(\S+)/)
        name = Mod::ModFile.package_name(match[1])
        return nil unless name
        root = File.join(dir, "#{name}.ri")
        root = "#{name}.ri" if dir == "."
        return File.file?(root) ? root : nil
      end
    end
    nil
  end

  private def ok_usage : String
    name = Command.program_name
    <<-USAGE
      Usage: #{name} ok [--json] [--affected FILE]... [PATH]...

      Say whether the work is done. Runs, fastest first, against the
      project in the current directory (or the PATHs given):

          fmt     #{name} fmt --check
          tidy    #{name} mod tidy --check   (only when ris.mod exists)
          check   #{name} check ROOT         (the manifest's root module)
          vet     #{name} vet ROOT
          test    #{name} test

      One line per step. The first step that fails stops the run: its
      own output is shown, and a `next:` line names the command that
      fixes it. Exit 0 only when every step passed; otherwise 1.

      --json           the same verdict as data: ok, steps (name and
                       status), failed, output and next
      --affected FILE  (repeatable) passed to check and test, so only
                       what a change reaches is checked and tested
      USAGE
  end
end
