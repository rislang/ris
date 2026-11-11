# iyi: `iyi test` — the verify loop, with no framework to learn
# (AI_FIRST.md §2 #4).
#
# A test is a plain iyi program named `*_test.iyi`: it asserts by exiting
# non-zero, exactly the contract every gate in `test/cli/` already runs on,
# because this repository's own culture is the framework. No DSL, no
# registry — a program that prints what failed and exits 1 is a failing
# test, and one that exits 0 passed. The prelude's `assert` is that in one
# word, and `assert_eq` and its family say more of it: a failed check
# panics with the values and the site. (ris: a module's checks are spec
# blocks, `spec N.M`; iyi's `test "name" { }` is refused.)
#
#     iyi test              # every *_test.iyi under the current directory
#     iyi test dir file.iyi # these, recursing into directories
#     iyi test --json       # the run as data, for a harness
#     iyi test --affected FILE  # only tests whose imports reach FILE
#
# `--affected` is the edit loop's discount, and its rule is runtime truth,
# not a heuristic: a test is affected exactly when the changed file is in
# its transitive import closure — computed by parsing, never by compiling,
# because R-1 makes the import list syntax. Note what the rule is *not*:
# interface hashes. An edit that leaves a module's interface untouched
# still changes what a consumer's test executes, so "the surface did not
# move" exempts a consumer from *recompiling*, never from *re-running*.
# The closure is the whole answer, and it is exact.
#
# Each test builds and runs alone: one file, one process, one verdict — a
# crash, a panic and a deadlock are all failures that name their file. A
# test that neither exits nor fails is killed at the deadline (`--timeout`,
# 60 s default), because a harness that can hang is not a harness.
class Iyi::Command
  # The longest `--timeout`: what Windows' waitable timer can count, in
  # 100 ns ticks held in an `Int64` - 922,337,203,684 s, some 29,000 years.
  # Past what the event loops' arithmetic holds a wait went wrong: 1e300
  # overflowed the span the wait becomes, and 9.3e14, 9.2e15 and 4.6e18
  # each hung a test that ends at once past a minute in one run on
  # Windows, and did not in the next.
  private MAX_TEST_WAIT = (Int64::MAX // 10_000_000 - 1).to_f

  # One run: a test program, or (ris) a module built with `build --spec`,
  # whose blocks are the JSON lines it wrote (doc/drafts/spec-blocks, 5.8);
  # `blocks` is nil for a test program.
  private alias TestResult = {file: String, status: String, seconds: Float64,
                              output: String, blocks: Array(JSON::Any)?}

  private def test
    as_json = false
    timeout = 60.0
    paths = [] of String
    affected = [] of String
    jobs = test_default_jobs

    while option = options.shift?
      case option
      when "--json"
        as_json = true
      when "-j", "--jobs"
        value = options.shift?
        jobs = value.try(&.to_i?) || 0
        unless jobs > 0
          abort! "-j takes a number of tests to run at once, not '#{value}'", :USAGE_ERROR
        end
      when "--timeout"
        value = options.shift?
        abort! "--timeout takes seconds", :USAGE_ERROR unless value
        timeout = value.to_f? || abort! "--timeout takes seconds, not '#{value}'", :USAGE_ERROR
        # `0` and `-1` were taken and every test came back "hung: killed
        # at -1.0s" - a verdict about the flag, printed as one about the
        # tests. A wait is a positive number of seconds, and one the clock
        # can count (`MAX_TEST_WAIT`): `1e300` overflowed the span it
        # becomes after the test was built, "Arithmetic overflow
        # (OverflowError)" and "you've found a bug in the iyi compiler", as
        # `inf` once did; `nan` is not a number of anything.
        unless timeout.finite? && timeout > 0 && timeout <= MAX_TEST_WAIT
          abort! "--timeout takes seconds to wait, and #{value} is not a wait", :USAGE_ERROR
        end
      when "--affected"
        # `.presence`: `--affected ""` is `"$FILE"` with `FILE` unset, and it
        # ran every test with " is not there" as the reason.
        value = options.shift?.presence
        abort! "--affected takes a changed file", :USAGE_ERROR unless value
        if Dir.exists?(value)
          abort! "#{value} is a directory, not a changed file", :USAGE_ERROR
        end
        affected << value
      when "--help", "-h"
        puts test_usage
        exit
      when .starts_with?('-')
        # A flag is a flag: this fell through to the path list and came
        # back as "no such file or directory: --nonesuch", which sends
        # the reader looking for a file they did not name.
        abort! "test: unknown flag #{option}", :USAGE_ERROR
      else
        paths << option
      end
    end
    paths << "." if paths.empty?

    files = [] of String
    paths.each do |path|
      # `iyi test ""` - `"$DIR"` with `DIR` unset - answered "no such file
      # or directory: ", a sentence with a hole where the name goes. No
      # path at all means the working directory on purpose; "" is not that.
      abort! "test takes paths, and '' is not one (no path at all runs the working directory)", :USAGE_ERROR if path.empty?
      if File.directory?(path)
        # ris: one walk (project_walk.cr) that skips lib/, mods/ and dot
        # directories; a glob ran the tests under lib/ (bug B1). The suffix
        # matches in any case, so `x_test.IYI` is refused below rather than
        # walked past (`Lexer.iyi_miscased?`).
        project_walk(path, files) { |name| test_program_name?(name) }
        # ris: and every module whose file holds spec blocks (5.9).
        candidates = [] of String
        project_walk(path, candidates) do |name|
          lower = name.downcase
          !test_program_name?(name) && (lower.ends_with?(".ri") || lower.ends_with?(".iyi"))
        end
        candidates.each { |file| files << file if spec_module?(file) }
      elsif File.file?(path)
        # As stored: `X_TEST.IYI` typed on Windows for `x_test.iyi` is it.
        files << Lexer.stored_name(path)
      else
        abort! "no such file or directory: #{path}", :USAGE_ERROR
      end
    end
    # One run per file, however many ways it was spelled: the list was made
    # unique as strings, so `iyi test . app\x_test.iyi app/x_test.iyi`
    # built and ran one test three times and reported "passed":3.
    files.uniq! { |file| Iyi.file_key(File.expand_path(file)) }.sort!
    if miscased = files.find { |file| Lexer.iyi_miscased?(file) }
      abort! Lexer.iyi_miscased_sentence(miscased), :USAGE_ERROR
    end

    if files.empty?
      abort! "no spec blocks, *_test.ri or *_test.iyi found. A proof is a `spec N.M` block at the end of a module", :USAGE_ERROR
    end

    skipped = 0
    discount_off = [] of String
    # The manifest is not a module, so no test's import closure holds it —
    # and a change to it is the largest change a workspace can make: every
    # `import example.test/user/liba` resolves through the requirement it
    # names, so bumping a version moves the code under every test at once.
    # `--affected iyi.mod` answered "0 to run, 1 skipped: no test's imports
    # reach the change", which is an agent bumping a dependency and being
    # told there is nothing to run.
    manifest_changed = affected.select do |changed|
      Iyi::Mod::Installer::MANIFESTS.includes?(File.basename(changed)) || Iyi::Mod::Sum::FILES.includes?(File.basename(changed))
    end
    # A changed file no import can name is the same largest change: the
    # prelude is compiled by every test and imported by none, and a file
    # that is not a module reaches a test through a macro (`Eiy.embed`,
    # `read_file`) or while it runs. An edit to `page.eiy` was answered "0
    # to run, 1 skipped: no test's imports reach the change", and the test
    # that renders it failed under a plain `iyi test`.
    unimported = affected.select do |changed|
      File.file?(changed) && !manifest_changed.includes?(changed) && outside_every_closure?(changed)
    end
    unless affected.empty? || !manifest_changed.empty? || !unimported.empty?
      # A changed file that no longer exists cannot be proven untouched by
      # anything. The closure does see a deleted *import* now — an import
      # names a path, and the path outlives the file — but a test also
      # depends on what it reads while it runs, and a fixture that is gone
      # was never in any closure. Deletion turns the discount off.
      #
      # Out loud, though. It used to turn off in silence, so a caller who
      # mistyped a path got a full run that looked like a selective one —
      # and the selection is this flag's whole claim: exact, computed by
      # parsing. A typo and a deletion look the same from here, which is
      # the other reason to say which file it was.
      discount_off = affected.reject { |changed| File.file?(changed) }
      if discount_off.empty?
        changed = affected.map { |changed| Iyi.file_key(File.expand_path(changed)) }
        selected = files.select do |file|
          closure = test_import_closure(file)
          closure.nil? || closure.any? { |path| changed.includes?(Iyi.file_key(path)) }
        end
        skipped = files.size - selected.size
        files = selected
      end
    end

    if files.empty?
      # An empty selection is a verdict, not an error: nothing that runs
      # any changed file exists, so there is nothing to re-run.
      if as_json
        puts %({"tests": [], "passed": 0, "failed": 0, "todo": 0, "skipped": #{skipped}})
      else
        puts "0 to run, #{skipped} skipped: no test's imports reach the change"
      end
      exit
    end

    results = run_tests(files, timeout, jobs)
    # ris: exit 77 is todo (SPEC 6.9), neither pass nor fail.
    todos = results.count { |result| result[:status] == "todo" }
    failed = results.count { |result| !result[:status].in?("pass", "todo") }

    if as_json
      JSON.build(STDOUT) do |json|
        json.object do
          json.field "tests" do
            json.array do
              results.each do |result|
                json.object do
                  json.field "file", result[:file]
                  json.field "status", result[:status]
                  json.field "seconds", result[:seconds]
                  json.field "output", result[:output] unless result[:output].empty?
                  if blocks = result[:blocks]
                    json.field "blocks" do
                      json.array { blocks.each(&.to_json(json)) }
                    end
                  end
                end
              end
            end
          end
          json.field "passed", results.size - failed - todos
          json.field "failed", failed
          json.field "todo", todos
          json.field "skipped", skipped
          # The caller asked for a selective run and did not get one. In
          # data, because the caller that passes `--affected` is usually a
          # program.
          unless discount_off.empty?
            json.field "affected_not_found" do
              json.array { discount_off.each { |missing| json.scalar missing } }
            end
          end
          unless manifest_changed.empty?
            json.field "affected_manifest" do
              json.array { manifest_changed.each { |name| json.scalar name } }
            end
          end
          unless unimported.empty?
            json.field "affected_not_imported" do
              json.array { unimported.each { |name| json.scalar name } }
            end
          end
        end
      end
      STDOUT.puts
    else
      results.each do |result|
        if blocks = result[:blocks]
          # ris: one line per block, its failed lines under it (5.8).
          blocks.each { |block| print_spec_block(block) }
          next if blocks.size > 0 && result[:status].in?("pass", "todo", "fail")
        end
        next if result[:status] == "pass"
        STDOUT << result[:file] << ": " << result[:status] << '\n'
        result[:output].each_line { |line| STDOUT << "  " << line << '\n' }
      end
      unless manifest_changed.empty?
        puts "#{manifest_changed.join(", ")} changed, so every test ran: the " \
             "requirements are what every package import resolves through"
      end
      unless unimported.empty?
        puts "#{unimported.join(", ")} is not a module an import can name, so every test ran: " \
             "the prelude, a file a macro reads and a fixture reach a test without an import"
      end
      unless discount_off.empty?
        puts "#{discount_off.join(", ")} is not there, so every test ran: " \
             "a file that is gone cannot be proven untouched by anything"
      end
      modules = results.select(&.[:blocks])
      programs = results.reject(&.[:blocks])
      parts = [] of String
      unless modules.empty?
        blocks = modules.flat_map { |result| result[:blocks].not_nil! }
        count = ->(status : String) { blocks.count { |block| block["status"]?.try(&.as_s?) == status } }
        unbuilt = modules.count { |result| !result[:status].in?("pass", "todo", "fail") }
        part = "#{modules.size} module#{modules.size == 1 ? "" : "s"}, #{blocks.size} blocks: " \
               "#{count.call("ok")} ok, #{count.call("broken")} broken, #{count.call("todo")} todo"
        part += ", #{unbuilt} not run" unless unbuilt.zero?
        parts << part
      end
      unless programs.empty?
        p_todos = programs.count { |result| result[:status] == "todo" }
        p_failed = programs.count { |result| !result[:status].in?("pass", "todo") }
        tail = p_todos.zero? ? "" : ", #{p_todos} todo"
        parts << "#{programs.size - p_failed - p_todos} passed, #{p_failed} failed#{tail}"
      end
      line = parts.join("; ")
      line += ", #{skipped} skipped" unless skipped.zero?
      puts line + (failed.zero? ? "" : " — a failing test prints above")
    end

    exit 1 unless failed.zero?
  end

  # iyi: whether no import closure can hold *path*, so no selection by
  # closure can discount anything for it: a file that is not a module
  # (`page.eiy`, a fixture, a `.cr` file), or one of the prelude's, which
  # every program compiles and no import names. `--affected
  # src/iyi/prelude.iyi` answered "0 to run, 1 skipped".
  private def outside_every_closure?(path : String) : Bool
    return true unless File.extname(path).compare(".iyi", case_insensitive: true) == 0 || File.extname(path).compare(".ri", case_insensitive: true) == 0
    key = Iyi.file_key(File.expand_path(path))
    IyiPath.default_paths.each do |entry|
      prelude = File.expand_path(File.join(entry, "iyi"))
      next unless File.file?(File.join(prelude, "prelude.iyi"))
      return !Iyi.path_under?(key, Iyi.file_key(prelude)).nil?
    end
    false
  end

  # The test's transitive import closure, as absolute paths, the test file
  # included — computed the way `mod context` reads imports: by parsing,
  # never compiling. Returns nil when the *test itself* does not parse:
  # nothing about it can be proven, so the caller must select it and let
  # its build say what is wrong. An imported file that does not parse is
  # already in the closure by path, which is all selection needs — and so
  # is one that is not there at all: an import names a path (R-1), and the
  # path stays named after the file is deleted. `check --affected` on a
  # deleted module used to answer "0 consumer(s) checked, all compile",
  # exit 0, about the one change certain to break every importer, because
  # the closure dropped what it could not open.
  private def test_import_closure(file : String) : Set(String)?
    entry = File.expand_path(file)
    # IV.6 read backwards, the rule a build applies
    # (`Compiler.entry_root_of`): a file whose path ends with its own
    # `module` header's path names the project root above both, and its
    # imports and its manifest resolve from there. A header-less script
    # keeps the entry-dir rule.
    entry_dir = closure_root_of(entry)
    table = Mod::Installer.table_for(entry_dir)
    closure = Set(String).new
    # ris: the entry's spec section too: its test-only imports (5.6) are
    # in the test program, so a change to one is a change under it.
    entry_imports = test_imports_of(entry, keep_spec: true)
    return nil unless entry_imports
    closure << entry
    queue = entry_imports.map do |written|
      named, _name = mod_context_names(written, entry_dir, table)
      File.expand_path(named)
    end
    while path = queue.pop?
      next unless closure.add?(path)
      (test_imports_of(path) || [] of String).each do |written|
        named, _name = mod_context_names(written, entry_dir, table)
        queue << File.expand_path(named)
      end
    end
    closure
  end

  private def test_imports_of(path : String, keep_spec = false) : Array(String)?
    parser = Parser.new(File.read(path))
    parser.filename = path
    parser.ris_keep_spec = keep_spec
    nodes = parser.parse
    imports = [] of String
    mod_context_collect(nodes, imports)
    imports.uniq!
  rescue CodeError | IO::Error
    nil
  end

  # ris: a test-only import (5.6) of a module that imports *file* back:
  # the proof belongs in that module. The refusal, or nil.
  private def spec_import_cycle(file : String) : String?
    entry = File.expand_path(file)
    entry_dir = closure_root_of(entry)
    table = Mod::Installer.table_for(entry_dir)
    plain = test_imports_of(entry) || return
    section = (test_imports_of(entry, keep_spec: true) || return) - plain
    key = Iyi.file_key(entry)
    section.each do |written|
      named, _ = mod_context_names(written, entry_dir, table)
      start = File.expand_path(named)
      seen = Set(String).new
      queue = [start]
      while path = queue.pop?
        next unless seen.add?(path)
        if Iyi.file_key(path) == key
          own = File.basename(entry).rchop(".ri").rchop(".iyi")
          other = written.rpartition('/')[2]
          return "the proof of #{own} imports #{other}, which imports " \
                 "#{own}; prove it in #{File.basename(start)}"
        end
        (test_imports_of(path) || [] of String).each do |next_written|
          next_named, _ = mod_context_names(next_written, entry_dir, table)
          queue << File.expand_path(next_named)
        end
      end
    end
    nil
  end

  # ris: an undefined name in a spec build that the `p/spec` module of a
  # package in *file*'s import closure defines (5.16): the import to add.
  private def spec_vocabulary_hint(file : String, output : String) : String?
    names = [] of String
    output.each_line do |line|
      next unless at = line.index("undefined ")
      open = line.index('\'', at) || next
      close = line.index('\'', open + 1) || next
      names << line[(open + 1)...close]
    end
    return if names.empty?
    entry = File.expand_path(file)
    entry_dir = closure_root_of(entry)
    table = Mod::Installer.table_for(entry_dir)
    packages = [] of String
    seen = Set(String).new
    queue = [entry]
    while path = queue.shift?
      next unless seen.add?(path)
      (test_imports_of(path, keep_spec: path == entry) || [] of String).each do |written|
        segments = written.split('/')
        packages << segments[0] if segments.size > 1 && segments[0] != "std"
        named, _ = mod_context_names(written, entry_dir, table)
        queue << File.expand_path(named)
      end
    end
    packages.uniq.each do |package|
      vocabulary = "#{package}/spec"
      named, _ = mod_context_names(vocabulary, entry_dir, table)
      source = File.file?(named) ? File.read(named) : next
      name = names.find do |undefined|
        source.each_line.any? do |line|
          words = line.tr("(:", "  ").split
          words.shift if words.first? == "pub"
          words[0]? == "def" && words[1]?.try(&.lchop("self.")) == undefined
        end
      end
      next unless name
      return "#{vocabulary} defines `#{name}`; add `import #{vocabulary}::*` after the first `spec` block"
    end
    nil
  end

  # IV.6 read backwards, which is the build's own rule: one reading of it,
  # because a selection that placed a test differently from the build that
  # compiles it would discount the wrong tests.
  private def closure_root_of(path : String) : String
    Compiler.entry_root_of(path, File.read(path))
  rescue IO::Error
    File.dirname(path)
  end

  # ris: `RIS_JOBS`, else the CPU count: how many tests build and run at once.
  private def test_default_jobs : Int32
    if env = ENV["RIS_JOBS"]?.presence
      value = env.to_i?
      return value if value && value > 0
      abort! "RIS_JOBS takes a number of tests to run at once, not '#{env}'", :USAGE_ERROR
    end
    Math.max(System.cpu_count.to_i, 1)
  end

  # ris: up to *jobs* tests at once, each built and run in its own process;
  # the results come back in *files*' order, so the report does not depend
  # on which test ended first.
  private def run_tests(files : Array(String), deadline : Float64, jobs : Int32)
    return files.map { |file| run_one_test(file, deadline) } if jobs <= 1 || files.size <= 1
    results = Array(TestResult?).new(files.size, nil)
    next_index = 0
    finished = ::Channel(Nil).new
    workers = Math.min(jobs, files.size)
    workers.times do
      spawn do
        while next_index < files.size
          index = next_index
          next_index += 1
          results[index] = run_one_test(files[index], deadline)
        end
        finished.send(nil)
      end
    end
    workers.times { finished.receive }
    results.map(&.not_nil!)
  end

  private def run_one_test(file : String, deadline : Float64) : TestResult
    started = Time.instant
    output = IO::Memory.new
    # ris: a module with spec blocks, not a test program: built with
    # `build --spec`, its blocks read from the JSON lines it writes (5.8).
    spec = !test_program_name?(File.basename(file))
    stdout = spec ? IO::Memory.new : output
    blocks = spec ? [] of JSON::Any : nil

    # With the executable's extension, which `build -o` appends to a name
    # that has none: without it the delete below asked for a name nothing
    # had, and on Windows every test left its program and its `.pdb` in
    # %TEMP%.
    binary = File.tempname("iyi-test", {{ flag?(:win32) ? ".exe" : nil }})
    # ris: a program file's blocks run its plain binary (5.7), built
    # first as `ris build` builds it.
    plain = spec && spec_program_file?(file) ? File.tempname("ris-program", {{ flag?(:win32) ? ".exe" : nil }}) : nil
    begin
      if spec && (cycle = spec_import_cycle(file))
        output << cycle << '\n'
        return {file: file, status: "does not build", seconds: elapsed(started), output: output.to_s, blocks: blocks}
      end
      if plain
        built = Process.run(Process.executable_path.not_nil!, ["build", file, "-o", plain],
          output: output, error: output)
        unless built.success?
          return {file: file, status: "does not build", seconds: elapsed(started), output: output.to_s, blocks: blocks}
        end
      end
      build_status = Process.run(
        Process.executable_path.not_nil!,
        spec ? ["build", "--spec", file, "-o", binary] : ["build", file, "-o", binary],
        output: output, error: output,
      )
      unless build_status.success?
        if spec && (hint = spec_vocabulary_hint(file, output.to_s))
          output << hint << '\n'
        end
        return {file: file, status: "does not build", seconds: elapsed(started), output: output.to_s, blocks: blocks}
      end

      env = spec ? {"RIS_SPEC_JSON" => "1"} : nil
      env["RIS_SPEC_PROGRAM"] = plain if env && plain
      process = Process.new(binary, env: env, output: stdout, error: output)
      tree = TestTree.new(process)
      running = tree
      done = ::Channel(Process::Status).new
      spawn { done.send(process.wait) }
      select
      when status = done.receive
        todo = status.exit_reason.normal? && status.exit_code == 77
        verdict = status.success? ? "pass" : todo ? "todo" : "fail"
        # A test the kernel killed printed "fail" and nothing under it -
        # the one failure with no evidence of its own, and the one an
        # infinite recursion produces. The death is the evidence.
        spec_blocks(stdout, output, blocks) if blocks
        evidence = output.to_s
        unless status.success? || todo || status.exit_reason.normal?
          evidence += "\n" unless evidence.empty? || evidence.ends_with?('\n')
          evidence += Command.death_sentence(status) + "\n"
        end
        {file: file, status: verdict, seconds: elapsed(started), output: status.success? ? "" : evidence, blocks: blocks}
      when timeout(deadline.seconds)
        # The test and whatever it started: its output is copied through
        # a pipe, and `wait` waits for that pipe's end, which a child the
        # test started holds open. Only the test was killed, so a test
        # that ran `ping -n 25` answered "hung: killed at 3.0s" after 25
        # seconds, with the pings printed after the kill, and one whose
        # child never ends hung `iyi test` for good.
        tree.terminate
        done.receive
        spec_blocks(stdout, output, blocks) if blocks
        {file: file, status: "hung: killed at #{deadline}s", seconds: elapsed(started), output: output.to_s, blocks: blocks}
      end
    ensure
      running.try &.close
      File.delete?(binary)
      plain.try { |path| File.delete?(path) }
      # And what the link wrote beside it: MSVC's `.pdb`, and on darwin the
      # `.dwarf` dsymutil makes, which the new check found there too.
      {% if flag?(:win32) %}
        File.delete?(binary.rchop(".exe") + ".pdb")
      {% elsif flag?(:darwin) %}
        File.delete?("#{binary}.dwarf")
      {% end %}
    end
  end

  # ris: whether *file* is a program file (5.5): top-level code before its
  # spec section. One that does not parse is built as a module, whose
  # build then reports it.
  private def spec_program_file?(file : String) : Bool
    parser = Parser.new(File.read(file))
    parser.filename = file
    parser.ris_raw_top = true
    nodes = parser.parse
    Parser.ris_program_file?(nodes.is_a?(Expressions) ? nodes.expressions : [nodes] of ASTNode)
  rescue
    false
  end

  # ris: whether *file* holds a spec section: a line that starts `spec N`
  # (5.9; `build --spec` then parses it and refuses a wrong shape).
  private def spec_module?(file : String) : Bool
    File.each_line(file) do |line|
      return true if line.starts_with?("spec ") && line[5]?.try(&.ascii_number?)
    end
    false
  rescue File::Error
    false
  end

  # The JSON lines a spec build wrote, one per block; any other line the
  # program printed goes to its output.
  private def spec_blocks(stdout : IO::Memory, output : IO::Memory, blocks : Array(JSON::Any)) : Nil
    stdout.to_s.each_line do |line|
      if line.starts_with?("{\"clause\":")
        begin
          blocks << JSON.parse(line)
          next
        rescue JSON::ParseException
        end
      end
      output << line << '\n'
    end
  end

  # `ok|BROKEN|todo  spec N.M  file:line`, then each failure (5.2).
  private def print_spec_block(block : JSON::Any) : Nil
    status = block["status"]?.try(&.as_s?) || "?"
    word = status == "broken" ? "BROKEN" : status
    STDOUT << word << "  spec " << block["clause"]? << "  " << block["file"]? << ':' << block["line"]?
    if status == "todo" && (reason = block["reason"]?.try(&.as_s?))
      STDOUT << "  " << reason
    end
    STDOUT << '\n'
    block["failures"]?.try(&.as_a?).try &.each do |failure|
      failure.as_s.each_line { |line| STDOUT << "  " << line << '\n' }
    end
  end

  # A test's program and what it starts, ended together: on Windows a job
  # object the program is put in as soon as it runs; elsewhere the program
  # alone. [INFERENCE] A child a test starts on Linux or darwin outlives
  # the kill and holds the pipe the same way; unmeasured there.
  private class TestTree
    @process : Process
    {% if flag?(:win32) %}
      @job : LibC::HANDLE = LibC::HANDLE.null
    {% end %}

    def initialize(@process : Process)
      {% if flag?(:win32) %}
        job = LibC.CreateJobObjectW(Pointer(LibC::SECURITY_ATTRIBUTES).null, Pointer(UInt16).null)
        return if job.null?
        # PROCESS_TERMINATE | PROCESS_SET_QUOTA, what assigning asks for.
        handle = LibC.OpenProcess(0x0001_u32 | 0x0100_u32, 0, @process.pid.to_u32)
        if handle.null?
          LibC.CloseHandle(job)
          return
        end
        assigned = LibC.AssignProcessToJobObject(job, handle)
        LibC.CloseHandle(handle)
        if assigned == 0
          LibC.CloseHandle(job)
          return
        end
        @job = job
      {% end %}
    end

    def terminate : Nil
      {% if flag?(:win32) %}
        unless @job.null?
          LibC.TerminateJobObject(@job, 1)
          LibC.CloseHandle(@job)
          @job = LibC::HANDLE.null
          return
        end
      {% end %}
      @process.terminate(graceful: false)
    end

    # The job's handle, once the test is over; closing it ends nothing.
    def close : Nil
      {% if flag?(:win32) %}
        LibC.CloseHandle(@job) unless @job.null?
        @job = LibC::HANDLE.null
      {% end %}
    end
  end

  private def elapsed(started : Time::Instant) : Float64
    (Time.instant - started).total_seconds.round(3)
  end

  private def test_usage
    <<-USAGE
    Usage: #{Command.program_name} test [--json] [-j N] [--timeout SECONDS] [--affected FILE]... [paths]

    Runs every `*_test.ri` and `*_test.iyi` under the given paths (default:
    `.`). A test is a plain program: exit 0 is a pass, exit 77 (`todo
    "reason"`) is todo, anything else is a failure that prints its own
    evidence. Only failures make the exit non-zero. `--json` reports the
    run as data.

    `--affected FILE` (repeatable) runs only the tests whose transitive
    import closure contains a named file — name every file you changed.
    The closure is read by parsing, so selection costs milliseconds; a
    deleted file turns the discount off, because nothing can prove the
    tests that imported it unaffected.

    `-j N` builds and runs up to N tests at once (default: `RIS_JOBS`, else
    the CPU count; `-j 1` runs them one by one). The report keeps the file
    order whatever finishes first.
    USAGE
  end
end
