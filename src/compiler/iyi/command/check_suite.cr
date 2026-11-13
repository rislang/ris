# ris: `ris check` — one verb that says whether the work is done.
#
# `ris check PART` runs one part in this process: format, deps, spec,
# types, unused or test, each an existing verb's verdict. Bare `ris check` runs
# every part by spawning the public `ris check PART ...` forms: every verb
# ends in `exit`, so running one in this process would end the run at the
# first part. format, deps and spec run first, in order; types, unused and test
# then run at once. The report shows the first failure in this fixed order
# and names the command that fixes it.
#
# `--fix` writes only at the start: format and deps are fixed when their
# check fails. Types edits are applied only when `types` is named.
require "json"

class Iyi::Command
  OK_STEP_WIDTH = 7
  OK_TIME_WIDTH = 11

  CHECK_PARTS = %w(format deps spec types unused test)

  private record OkStep, name : String, runs : Array(Array(String)),
    next_hint : String

  private def check_command
    part = nil
    if (first = options.first?) && CHECK_PARTS.includes?(first)
      part = options.shift
    end
    fixing = false
    json = false
    jobs = nil
    affected = [] of String
    paths = [] of String
    while option = options.shift?
      case option
      when "--help", "-h"
        puts check_usage
        exit
      when "--fix", "-f"
        if option == "-f" && options.first?.in?("json", "text")
          abort! "check: -f is --fix now; for data use --json " \
                 "(the types step carries the diagnostics)", :USAGE_ERROR
        end
        fixing = true
      when "--format"
        abort! "check: --format is gone; use --json " \
               "(the types step carries the diagnostics)", :USAGE_ERROR
      when "--json"
        json = true
      when "--no-color"
        @color = false
      when "-j", "--jobs"
        value = options.shift?
        count = value.try(&.to_i?) || 0
        abort! "-j takes a number of tests to run at once, not '#{value}'", :USAGE_ERROR unless count > 0
        jobs = count.to_s
      when "--affected"
        value = options.shift?.presence
        abort! "--affected takes a changed file", :USAGE_ERROR unless value
        affected << value
      when .starts_with?('-')
        abort! "check: unknown flag #{option}. `#{Command.program_name} check --help` lists them", :USAGE_ERROR
      else
        abort! "check: no such file or directory: #{option}", :USAGE_ERROR unless File.exists?(option)
        paths << option
      end
    end

    if part == "types" && json
      abort! "check types: --fix prints text; run `#{Command.program_name} check types --fix`, " \
             "then `#{Command.program_name} check types --json`", :USAGE_ERROR if fixing
      check_types_json(paths, affected)
    elsif part && !json
      check_part(part, fixing, jobs, affected, paths)
    else
      check_suite(part ? [part] : CHECK_PARTS, fixing, json, jobs, affected, paths)
    end
  end

  # Why *part* has nothing to do here, or nil when it has work.
  private def check_skip(part : String, paths : Array(String),
                         affected : Array(String)) : String?
    case part
    when "format"
      "nothing to format" if format_sources(paths).empty?
    when "deps"
      if !paths.empty?
        "a PATH was given"
      elsif !Mod::Installer.manifest?(".")
        "no ris.mod here"
      end
    when "spec"
      if !paths.empty?
        "a PATH was given"
      elsif !(root = spec_root) || !spec_present?(root)
        "no SPEC.md"
      end
    when "types"
      "nothing to check" if affected.empty? && ok_targets(paths).empty?
    when "unused"
      "nothing to check" if ok_targets(paths).empty?
    when "test"
      # ris: a module with spec blocks is a test too (5.9): `ris init`
      # writes no *_test.ri, only a block at the end of NAME.ri.
      "no *_test.ri or spec block" unless ok_sources(paths).any? do |file|
        file.ends_with?("_test.ri") || spec_module?(file)
      end
    end
  end

  # One part, in this process; it ends the process with its verdict.
  private def check_part(part : String, fix : Bool, jobs : String?,
                         affected : Array(String),
                         paths : Array(String)) : NoReturn
    # A named path is fixed as given: fix.cr walks a directory itself.
    fixes_paths = part == "types" && fix && !paths.empty?
    if !fixes_paths && (why = check_skip(part, paths, affected))
      puts ok_line(part, "skip (#{why})")
      exit 0
    end
    case part
    when "format"
      options.replace((fix ? [] of String : ["--check"]) + format_sources(paths))
      format
    when "deps"
      options.replace(fix ? [] of String : ["--check"])
      mod_tidy
    when "spec"
      spec_check(fix)
    when "types"
      if fix
        # A named file or directory is fixed as given: fix.cr walks one.
        files = !affected.empty? ? affected : paths.empty? ? ok_targets(paths) : paths
        options.replace(files)
        self.fix
      elsif !affected.empty?
        options.replace(affected.flat_map { |file| ["--affected", file] })
        check_affected
      else
        check_each_target("types", ok_targets(paths)) do |target|
          options.replace([target])
          compile_no_codegen "check"
          report_warnings
          exit 1 if warnings_fail_on_exit?
        end
      end
    when "unused"
      check_each_target("unused", ok_targets(paths)) do |target|
        with_specs = spec_module?(target)
        options.replace(["--check", target])
        options.unshift("--spec") if with_specs
        unreachable "vet", with_specs, package_spec_modules(target)
      end
    when "test"
      options.replace((jobs ? ["-j", jobs] : [] of String) +
                      affected.flat_map { |file| ["--affected", file] } + paths)
      test
    end
    exit 0
  end

  # One target runs here; several each get their own process, since the
  # compile ends its process.
  private def check_each_target(part : String, targets : Array(String), &) : NoReturn
    if targets.size == 1
      yield targets.first
      exit 0
    end
    exe = Process.executable_path.not_nil!
    passed = targets.map do |target|
      Process.run(exe, ["check", part, target],
        output: :inherit, error: :inherit).success?
    end
    exit passed.all? ? 0 : 1
  end

  private def check_types_errors(targets : Array(String)) : Array(CodeError)
    targets.compact_map { |target| check_one_alone(target) }
  end

  # `ris check types --json`: the one-step object, the diagnostics in it.
  private def check_types_json(paths : Array(String),
                               affected : Array(String)) : NoReturn
    started = Time.instant
    status = "ok"
    errors = [] of CodeError
    if check_skip("types", paths, affected)
      status = "skip"
    else
      errors =
        if affected.empty?
          check_types_errors(ok_targets(paths))
        else
          check_affected_failures(affected).map(&.[1])
        end
      status = "fail" unless errors.empty?
    end
    seconds = (Time.instant - started).total_seconds
    failed = status == "fail"
    output = errors.join("\n") { |error| error.color = false; error.to_s }
    JSON.build(STDOUT) do |builder|
      builder.object do
        builder.field "ok", !failed
        builder.field "steps" do
          builder.array do
            builder.object do
              builder.field "name", "types"
              builder.field "status", status
              builder.field "seconds", seconds.round(1) unless status == "skip"
              builder.field "diagnostics" do
                builder.array do
                  errors.each do |error|
                    JSON.parse(error.to_json).as_a.each(&.to_json(builder))
                  end
                end
              end
            end
          end
        end
        builder.field "failed", failed ? "types" : nil
        builder.field "output", failed ? output : nil
        builder.field "next", failed ? check_next_hint("types", paths) : nil
        builder.field "seconds", seconds.round(1)
      end
    end
    puts
    exit failed ? 1 : 0
  end

  private def check_next_hint(part : String, paths : Array(String)) : String
    name = Command.program_name
    shown = paths.empty? ? "" : " " + Process.quote(paths)
    again = "then run #{name} check#{shown} again"
    case part
    when "format", "deps" then "#{name} check --fix#{shown}"
    when "spec"           then "fix what the lines above name (#{name} spec lists the clauses), #{again}"
    when "types"          then "#{name} check types --fix#{shown}"
    when "unused"         then "use or remove the unreachable methods named above, #{again}"
    else                       "fix the failing test, #{again}"
    end
  end

  private def check_suite(parts : Array(String), fix : Bool, json : Bool,
                          jobs : String?, affected : Array(String),
                          paths : Array(String)) : NoReturn
    affected_flags = affected.flat_map { |file| ["--affected", file] }
    steps = parts.map do |part|
      args = ["check", part]
      case part
      when "format", "deps", "spec"
        args << "--fix" if fix
      when "types"
        args << "--json" if json
        args.concat(affected_flags)
      when "test"
        args.concat(["-j", jobs]) if jobs
        args.concat(affected_flags)
      end
      args.concat(paths) unless part.in?("deps", "spec")
      runs = check_skip(part, paths, affected) ? [] of Array(String) : [args]
      OkStep.new(part, runs, check_next_hint(part, paths))
    end

    exe = Process.executable_path.not_nil!
    results = [] of {String, String, Float64?}
    failed = nil
    diagnostics = nil
    started = Time.instant
    output = ""

    # format, deps and spec run first, in order; types, unused and test run
    # at once. The lines and the failure shown are those of the first
    # failing step in this order, as if the steps ran one by one.
    runners = steps.map { |step| OkRunner.new(step, exe) }
    serial = true
    runners.each do |runner|
      next if runner.step.runs.empty?
      serial = false unless {"format", "deps", "spec"}.includes?(runner.step.name)
      if serial
        runner.run
        break unless runner.passed?
      else
        runner.start
      end
    end
    runners.each do |runner|
      step = runner.step
      if step.runs.empty?
        results << {step.name, "skip", nil}
        puts ok_line(step.name, "skip (#{check_skip(step.name, paths, affected)})") unless json
        next
      end
      passed = runner.passed?
      seconds = runner.seconds
      step_output = runner.output
      if step.name == "types" && json
        # The types step answers with its own one-step object.
        if line = step_output.lines.reverse.find(&.starts_with?('{'))
          begin
            parsed = JSON.parse(line)
            diagnostics = parsed["steps"][0]["diagnostics"]
            step_output = parsed["output"].as_s? || step_output
          rescue JSON::ParseException
          end
        end
      end
      results << {step.name, passed ? "ok" : "fail", seconds}
      puts ok_line(step.name, passed ? "ok" : "FAIL", seconds) unless json
      unless passed
        failed = step
        output = step_output
        break
      end
    end
    if failed
      # A later step still running is killed: its line says so.
      stopped = runners.select(&.running?)
      runners.each(&.cancel)
      unless json
        runners.each do |runner|
          puts ok_line(runner.step.name, "stopped") if stopped.includes?(runner)
        end
      end
    end
    total = (Time.instant - started).total_seconds

    if json
      JSON.build(STDOUT) do |builder|
        builder.object do
          builder.field "ok", failed.nil?
          builder.field "steps" do
            builder.array do
              results.each do |step_name, status, seconds|
                builder.object do
                  builder.field "name", step_name
                  builder.field "status", status
                  builder.field "seconds", seconds.round(1) if seconds
                  if step_name == "types"
                    builder.field "diagnostics" do
                      if found = diagnostics
                        found.to_json(builder)
                      else
                        builder.array { }
                      end
                    end
                  end
                end
              end
            end
          end
          builder.field "failed", failed.try(&.name)
          builder.field "output", failed ? output : nil
          builder.field "next", failed.try(&.next_hint)
          builder.field "seconds", total.round(1)
        end
      end
      puts
    elsif failed
      puts "FAIL in #{ok_seconds(total)}"
      puts
      print output
      puts unless output.empty? || output.ends_with?('\n')
      puts
      puts "next: #{failed.next_hint}"
    else
      puts "ok in #{ok_seconds(total)}"
    end
    exit(failed ? 1 : 0)
  end

  # One step's runs, one after another in a fiber; its verdict waits for
  # them. `cancel` kills what still runs once an earlier step failed.
  private class OkRunner
    getter step : OkStep
    @buffer = IO::Memory.new
    @passed : Bool? = nil
    @done = ::Channel(Nil).new(1)
    @process : Process? = nil
    @cancelled = false
    @started = false
    getter seconds : Float64 = 0.0

    def initialize(@step : OkStep, @exe : String)
    end

    def run : Nil
      @started = true
      began = Time.instant
      ok = @step.runs.all? do |args|
        break false if @cancelled
        process = Process.new(@exe, args, output: @buffer, error: @buffer)
        @process = process
        process.wait.success?
      end
      @process = nil
      @seconds = (Time.instant - began).total_seconds
      @passed = ok
      @done.send(nil)
    end

    def start : Nil
      @started = true
      spawn { run }
    end

    def passed? : Bool
      return false unless @started
      if @passed.nil?
        @done.receive
      end
      @passed.not_nil!
    end

    def running? : Bool
      @started && @passed.nil?
    end

    def output : String
      @buffer.to_s
    end

    def cancel : Nil
      @cancelled = true
      @process.try { |process| process.terminate(graceful: false) rescue nil }
    end
  end

  private def ok_line(name : String, status : String,
                      seconds : Float64? = nil) : String
    line = "#{name.ljust(OK_STEP_WIDTH)}#{status}"
    return line unless seconds
    time = ok_seconds(seconds)
    line + time.rjust({OK_TIME_WIDTH - status.size, time.size + 1}.max)
  end

  private def ok_seconds(seconds : Float64) : String
    "%.1fs" % seconds
  end

  # Every .ri file the PATHs hold (the current directory when none is
  # given), hidden directories and `lib` left out.
  private def ok_sources(paths : Array(String)) : Array(String)
    files = [] of String
    (paths.empty? ? ["."] : paths).each do |path|
      if File.file?(path)
        files << path if path.ris_source?
      elsif Dir.exists?(path)
        ok_walk(path, files)
      end
    end
    files
  end

  # What format reads: a named file as given (any source the formatter
  # reads), and the .ri files under each directory.
  private def format_sources(paths : Array(String)) : Array(String)
    return ok_sources(paths) if paths.empty?
    paths.flat_map { |path| File.file?(path) ? [path] : ok_sources([path]) }
  end

  private def ok_walk(dir : String, files : Array(String)) : Nil
    Dir.children(dir).sort!.each do |child|
      next if child.starts_with?('.')
      path = dir == "." ? child : File.join(dir, child)
      if Dir.exists?(path)
        ok_walk(path, files) unless child == "lib"
      elsif Lexer.iyi_named?(child)
        abort! Lexer.iyi_miscased_sentence(path), :USAGE_ERROR
      elsif child.ris_source?
        files << path
      end
    end
  end

  # The program files types and unused compile: each given .ri file, and
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
          abort! Lexer.iyi_miscased_sentence(File.join(dir, child)), :USAGE_ERROR if Lexer.iyi_named?(child)
          next unless child.ends_with?(".ri") && !child.ends_with?("_test.ri")
          files << (dir == "." ? child : File.join(dir, child))
        end
      end
    end
    files
  end

  # A library's root exports are proven by spec blocks in the package's
  # other modules: those modules count as callers of the root (ris check
  # unused). Empty unless *target* is the package's root module.
  private def package_spec_modules(target : String) : Array(String)
    dir = File.dirname(target)
    root = ok_root_module(dir)
    return [] of String unless root && File.expand_path(root) == File.expand_path(target)
    Dir.glob(File.join(dir, "**", "*.ri")).sort!.select do |file|
      !file.ends_with?("_test.ri") &&
        File.expand_path(file) != File.expand_path(target) &&
        spec_module?(file)
    end
  end

  private def ok_root_module(dir : String) : String?
    manifest = Mod::Installer.manifest_in(dir)
    manifest = nil unless File.file?(manifest)
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

  private def check_usage : String
    name = Command.program_name
    <<-USAGE
      Usage: #{name} check [PART] [--fix|-f] [-j N] [--json]
                       [--affected FILE]... [PATH]...

      Say whether the work is done. Reads only, unless --fix is given.
      PART is one of:

          format   the .ri files are formatted
          deps     ris.mod and ris.sum match the imports (only with no
                   PATH and a ris.mod in the current directory)
          spec     the spec's clauses and their tests agree (SPEC 6.8;
                   only with no PATH and a SPEC.md)
          types    each target type-checks: the manifest's root module,
                   else every non-test .ri file, or the files named
          unused   no method of a target is unreachable
          test     every *_test.ri passes

      With no PART every part runs: format, deps and spec first, then types,
      unused and test at once. One line per part with its wall time,
      in this order; `skip` when it has nothing to do, `stopped` when
      an earlier failure killed it. The first failure shows its output
      and a `next:` line naming the command that fixes it. A last line
      gives the total. Exit 0 only when every part passed.

      --fix, -f        fix format and deps when their check fails, then
                       check again. With `types` named: apply the
                       compiler's suggested edits (32 at most a file),
                       then check types. unused and test have no fixer.
      --json           the verdict as data: ok, steps (name, status,
                       seconds; types adds diagnostics, the compiler's
                       errors with suggested_edit), failed, output, next,
                       seconds
      --affected FILE  (repeatable) types and test only what a change
                       reaches
      -j N             tests run at once (default: RIS_JOBS, else the
                       CPU count)

      Quick loops: `#{name} check types FILE`, `#{name} test --affected FILE`.
      A path named like a part is reached as `./test`.
      USAGE
  end
end
