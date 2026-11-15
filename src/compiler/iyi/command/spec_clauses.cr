# ris: `ris spec` — the spec's clauses and the proofs that keep them
# (SPEC 6.7-6.9; design: doc/drafts/spec-cli/spec-cli.md, spec blocks
# and .spec.lock: doc/drafts/spec-blocks/spec-blocks.md 5.9-5.15).
#
#     ris spec              # one line per clause: status and tests
#     ris spec 1 / 1.3      # one chapter or clause, for an agent's context
#     ris spec ack 1.3      # .spec.lock (and tags) take 1.3's version
#     ris spec todo         # every todo test
#
# A clause is `* N.M text` under `## N. Title`; its version is the first 8
# hex digits of SHA-256 of its whitespace-normalised text. A test file
# under the root's test/ names clauses in its leading comment block:
# `# spec: 1.3@a4f20c19`. No regex: the compiler links no pcre (spec.cr's
# note, iyi SPEC III.10), and the grammar is small enough by hand.
require "json"

class Iyi::Command
  private SPEC_EXTENSIONS = {".ri", ".cr", ".sh", ".py"}

  private class SpecError < Exception
  end

  private record SpecClause, number : String, major : Int32, minor : Int32,
    text : String, version : String

  # One scanned test file: the clauses it names (version nil when it
  # names one without), whether it said `none`, and its todo reason.
  private class SpecTest
    getter path : String
    getter items = [] of {String, String?}
    property none : String? = nil
    property tagged = false
    getter tag_lines = {} of String => Int32
    property todo : String? = nil

    def initialize(@path : String)
    end

    def names?(number : String) : Bool
      items.any? { |item| item[0] == number }
    end
  end

  private record SpecEntry, heading : String, versions : Array(String)

  # ris: one `spec N.M` block in a module under the root (spec blocks
  # draft 5.9, 5.14): where it is, whether its body says `todo`, and the
  # clause label its line ends in (5.15), whitespace-collapsed.
  private record SpecBlock, path : String, line : Int32, number : String,
    reasons : Array(String), label : String? do
    def todo : Bool
      !reasons.empty?
    end
  end

  # Read by spec_status; set by spec_load_or_abort.
  @spec_blocks = [] of SpecBlock
  @spec_lock = {} of String => String
  @spec_owners = {} of String => {String, Int32}
  @spec_markers = {} of String => {String, Int32, String}
  # `nospec PATH NAME...` lines of .spec.lock (SPEC 6.8, R5).
  @spec_nospec = {} of String => Set(String)

  private def spec_command
    case options.first?
    when "--help", "-h"
      puts spec_usage
      exit
    when "ack"
      options.shift
      spec_ack
    when "todo"
      options.shift
      spec_todo
    end
    json = false
    target = nil
    while option = options.shift?
      case option
      when "--json" then json = true
      when .starts_with?('-')
        abort! "spec: unknown flag #{option}. `#{Command.program_name} spec --help` lists them", :USAGE_ERROR
      else
        abort! "spec: one clause or chapter at a time, not '#{option}' after #{target}", :USAGE_ERROR if target
        abort! "spec: '#{option}' is no clause number: write N, N.M, MODULE or MODULE.N", :USAGE_ERROR unless spec_target?(option)
        target = option
      end
    end
    root, clauses, tests = spec_load_or_abort
    if target
      spec_show(root, clauses, tests, target, json)
    else
      spec_report(clauses, tests, json)
    end
    exit
  end

  # ris: `build --spec`: the clauses a spec block may name are ROOT's
  # (doc/drafts/spec-blocks, 5.1). No spec there: the block's refusal
  # names the file to create.
  private def ris_spec_setup(compiler : Compiler) : Nil
    compiler.ris_spec = true
    root = spec_root
    unless root
      compiler.ris_spec_file = File.join(Dir.current, "SPEC.md")
      return
    end
    files = spec_files(root)
    compiler.ris_spec_file = files.size == 1 ? Iyi.relative_filename(files[0]) : "spec/*.md"
    if files.empty? && !Dir.exists?(File.join(root, "src"))
      compiler.ris_spec_file = Iyi.relative_filename(File.join(root, "SPEC.md"))
      return
    end
    compiler.ris_spec_clauses = spec_clauses(root).map(&.number).to_set
  rescue ex : SpecError
    abort! "build --spec: #{ex.message}", :FAILURE
  end

  # --- loading -------------------------------------------------------------

  private def spec_load_or_abort(root : String? = nil) : {String, Array(SpecClause), Array(SpecTest)}
    root ||= spec_root || abort!("spec: no SPEC.md here: none in the root (the nearest directory with ris.mod or " \
                               "ris.mod) nor in the current directory", :USAGE_ERROR)
    begin
      @spec_blocks = spec_blocks_of(root)
      @spec_lock = spec_lock_of(root)
      {root, spec_clauses(root), spec_tests(root)}
    rescue ex : SpecError
      abort! "spec: #{ex.message}", :FAILURE
    end
  end

  # The nearest directory holding ris.mod, else the current one
  # when it holds a spec (ris's own repository has no manifest).
  private def spec_root : String?
    dir = Dir.current
    loop do
      return dir if Mod::Installer.manifest?(dir)
      parent = File.dirname(dir)
      break if parent == dir
      dir = parent
    end
    here = Dir.current
    spec_present?(here) ? here : nil
  end

  private def spec_present?(root : String) : Bool
    return true if File.file?(File.join(root, "SPEC.md")) || Dir.exists?(File.join(root, "spec"))
    src = File.join(root, "src")
    return false unless Dir.exists?(src) && !File.symlink?(src)
    files = [] of String
    project_walk(src, files) { |name| name.ends_with?(".ri") }
    files.any? do |file|
      File.read_lines(file).any? do |line|
        line.starts_with?("# ") && spec_number?(line[2..].split.first? || "", chapter_ok: false)
      end
    end
  end

  private def spec_files(root : String) : Array(String)
    single = File.join(root, "SPEC.md")
    dir = File.join(root, "spec")
    has_dir = Dir.exists?(dir) && Dir.children(dir).any?(&.ends_with?(".md"))
    if File.file?(single) && has_dir
      raise SpecError.new("both SPEC.md and spec/*.md are here; keep one (a split spec is spec/N-name.md)")
    end
    return [single] if File.file?(single)
    return [] of String unless has_dir
    Dir.children(dir).select(&.ends_with?(".md")).sort_by! do |name|
      digits = name.each_char.take_while(&.ascii_number?).join
      {digits.to_i? || Int32::MAX, name}
    end.map { |name| File.join(dir, name) }
  end

  private def spec_clauses(root : String) : Array(SpecClause)
    clauses = [] of SpecClause
    @spec_markers.clear
    seen = Set(String).new
    spec_files(root).each do |file|
      shown = ::Path[file].relative_to(root).to_s
      chapter = nil
      current = nil
      lines = File.read_lines(file)
      flush = ->(entry : {String, Int32, Int32, Array(String)}?) do
        if entry
          text = entry[3].join(" ").split.join(" ")
          clauses << SpecClause.new(entry[0], entry[1], entry[2], text, spec_version(text))
        end
      end
      lines.each_with_index do |line, index|
        if line.includes?("<!-- todo:")
          entry = current
          valid = line.starts_with?("  <!-- todo: ") && line.ends_with?(" -->") &&
                  line.size <= 80
          reason = valid ? line[13...-4] : ""
          unless entry && valid && !reason.blank? && !@spec_markers.has_key?(entry[0])
            raise SpecError.new("#{shown}:#{index + 1}: misplaced or invalid todo marker; " \
                                "write one `  <!-- todo: reason -->` after the clause text, before a blank line")
          end
          @spec_markers[entry[0]] = {shown, index + 1, reason}
          next
        end
        if line.starts_with?("## ")
          flush.call(current)
          current = nil
          rest = line[3..]
          digits = rest.each_char.take_while(&.ascii_number?).join
          chapter = digits.empty? || rest[digits.size]? != '.' ? nil : digits.to_i
          next
        end
        if line.starts_with?("* ") && (number = spec_clause_number(line))
          flush.call(current)
          current = nil
          major, minor = number.split('.').map(&.to_i)
          unless chapter
            raise SpecError.new("#{shown}:#{index + 1}: clause #{number} is under no `## N. Title` heading")
          end
          unless major == chapter
            raise SpecError.new("#{shown}:#{index + 1}: clause #{number} is under chapter #{chapter}'s heading; " \
                                "a clause goes under the heading of its own chapter")
          end
          unless seen.add?(number)
            raise SpecError.new("#{shown}:#{index + 1}: clause #{number} is written twice; a new clause takes the " \
                                "next free number")
          end
          current = {number, major, minor, [line[(2 + number.size)..]]}
          next
        end
        if (entry = current) && !line.blank? && line[0].whitespace?
          if @spec_markers.has_key?(entry[0])
            raise SpecError.new("#{shown}:#{index + 1}: text after todo marker; move the marker after the clause text")
          end
          entry[3] << line
        else
          flush.call(current)
          current = nil
        end
      end
      flush.call(current)
    end
    spec_module_clauses(root, clauses, seen)
    clauses.sort_by! { |clause| spec_sort_key(clause.number) }
  end

  # `* 1.3 text` -> "1.3"; nil when the bullet holds no clause number.
  private def spec_clause_number(line : String) : String?
    rest = line[2..]
    word = rest.split(' ', 2).first
    return nil unless word[0]?.try(&.ascii_number?)
    return nil unless spec_number?(word, chapter_ok: false)
    return nil unless rest.size > word.size && rest[word.size] == ' '
    word
  end

  private def spec_number?(word : String, chapter_ok : Bool) : Bool
    parts = word.split('.')
    return false unless parts.size == 2 || (chapter_ok && parts.size == 1)
    if parts.size == 2 && spec_module_id?(parts[0])
      return !parts[1].empty? && parts[1][0] != '0' && parts[1].each_char.all?(&.ascii_number?)
    end
    parts.all? { |part| !part.empty? && part.each_char.all?(&.ascii_number?) }
  end

  private def spec_module_id?(word : String) : Bool
    return false if word.empty?
    word.split('/').each do |segment|
      return false if segment.empty?
      first = segment[0]
      return false unless first.in?('a'..'z') || first == '_'
      segment.each_char do |char|
        return false unless char.in?('a'..'z') || char.ascii_number? || char == '_'
      end
    end
    true
  end

  private def spec_target?(word : String) : Bool
    spec_number?(word, chapter_ok: true) || spec_module_id?(word)
  end

  private def spec_sort_key(number : String) : {Int32, String, Int32, Int32}
    prefix, _, suffix = number.rpartition('.')
    if spec_module_id?(prefix)
      {1, prefix, 0, suffix.to_i}
    else
      {0, "", prefix.to_i, suffix.to_i}
    end
  end

  private def spec_selected?(clause : SpecClause, target : String) : Bool
    clause.number == target || clause.number.rpartition('.')[0] == target
  end

  private def spec_owner?(block : SpecBlock) : Bool
    @spec_owners[block.number]? == {block.path, block.line}
  end

  private def spec_module_clauses(root : String, clauses : Array(SpecClause),
                                  seen : Set(String)) : Nil
    @spec_owners.clear
    src = File.join(root, "src")
    return unless Dir.exists?(src) && !File.symlink?(src)
    files = [] of String
    project_walk(src, files) { |name| name.ends_with?(".ri") }
    modules = {} of String => String
    files.sort!.each do |file|
      path = ::Path[file].relative_to(src).to_s
      mod = path[0...-File.extname(path).size]
      mod = mod[4..] if mod.starts_with?("std/")
      shown = ::Path[file].relative_to(root).to_s
      if other = modules[mod]?
        raise SpecError.new("two files are module #{mod}: #{other}, #{shown}; " \
                            "keep one file for module #{mod}")
      end
      modules[mod] = shown
    end
    modules.each do |mod, shown|
      lines = File.read_lines(File.join(root, shown))
      lines.each_with_index do |line, index|
        next unless line.starts_with?("# ")
        rest = line[2..]
        number = rest.split(' ', 2).first
        prefix, dot, suffix = number.rpartition('.')
        next if dot.empty? || prefix.empty? || prefix[0].ascii_number?
        next unless suffix[0]?.try { |c| c.ascii_number? || c == '-' }
        stop = index + 1
        while stop < lines.size && lines[stop].starts_with?('#')
          stop += 1
        end
        head = stop < lines.size ? spec_block_head(lines[stop]) : nil
        owns = head && head[0] == number
        next unless prefix == mod || owns
        if prefix != mod
          base = shown.starts_with?("src/std/") ? "src/std" : "src"
          destination = modules[prefix]? || "#{base}/#{prefix}#{File.extname(shown)}"
          raise SpecError.new("#{shown}:#{index + 1}: module #{prefix} does not match #{mod}; " \
                              "move it to #{destination}")
        end
        unless spec_module_id?(mod) && spec_number?(number, chapter_ok: false)
          raise SpecError.new("#{shown}:#{index + 1}: invalid module clause #{number}; " \
                              "write MODULE.N with lowercase path segments and N positive, without leading zeros")
        end
        unless owns
          raise SpecError.new("#{shown}:#{index + 1}: orphan clause #{number}; " \
                              "put `spec #{number}` directly after its comment")
        end
        unless seen.add?(number)
          raise SpecError.new("#{shown}:#{index + 1}: duplicate owner of #{number}; " \
                              "keep one owning comment and block; give a new clause the next free number")
        end
        if head.not_nil![1]
          raise SpecError.new("#{shown}:#{stop + 1}: owning block takes no label; write `spec #{number}`")
        end
        unless rest.starts_with?(number + " ") && !rest[(number.size + 1)..].blank?
          raise SpecError.new("#{shown}:#{index + 1}: clause needs text; write `# #{number} text`")
        end
        text = [rest[(number.size + 1)..]]
        lines[(index + 1)...stop].each do |continuation|
          unless continuation.starts_with?("#   ")
            raise SpecError.new("#{shown}:#{index + 1}: invalid continuation; write `#   text`")
          end
          text << continuation[4..]
        end
        normalized = text.join(" ").split.join(" ")
        clauses << SpecClause.new(number, 0, suffix.to_i, normalized, spec_version(normalized))
        @spec_owners[number] = {shown, stop + 1}
      end
    end
  end

  private def spec_version(text : String) : String
    SpecSha256.hexdigest(text.to_slice)[0, 8]
  end

  private def spec_tests(root : String) : Array(SpecTest)
    found = [] of String
    dir = File.join(root, "test")
    spec_walk(dir, found) if Dir.exists?(dir)
    found.sort!.map { |file| spec_read_test(root, file) }
  end

  private def spec_walk(dir : String, found : Array(String)) : Nil
    Dir.children(dir).each do |child|
      next if child.starts_with?('.')
      path = File.join(dir, child)
      if File.symlink?(path)
        next
      elsif Dir.exists?(path)
        spec_walk(path, found)
      elsif SPEC_EXTENSIONS.includes?(File.extname(child))
        found << path
      end
    end
  end

  private def spec_read_test(root : String, file : String) : SpecTest
    shown = ::Path[file].relative_to(root).to_s
    test = SpecTest.new(shown)
    lines = begin
      File.read_lines(file)
    rescue IO::Error
      [] of String
    end
    spec_leading_block(lines).each do |index|
      if rest = spec_tag_rest(lines[index])
        test.tagged = true
        spec_parse_tag(test, rest, "#{shown}:#{index + 1}")
        test.items.each { |number, _| test.tag_lines[number] ||= index + 1 }
      end
    end
    unless test.tagged
      lines.each do |line|
        stripped = line.lstrip
        next unless stripped.starts_with?('#')
        spec_prose_numbers(stripped).each do |number|
          test.items << {number, nil} unless test.names?(number)
        end
      end
    end
    if file.ends_with?(".ri")
      lines.each do |line|
        if reason = spec_todo_reason(line)
          test.todo = reason
          break
        end
      end
    end
    test
  end

  # ris: every spec block in a `.ri` / `.ri` file under *root*, walked
  # as `ris test` walks (5.9): blocks in src/ count too (bug B2).
  private def spec_blocks_of(root : String) : Array(SpecBlock)
    files = [] of String
    project_walk(root, files) do |name|
      lower = name.downcase
      lower.ends_with?(".ri")
    end
    blocks = [] of SpecBlock
    files.sort!.each do |file|
      lines = begin
        File.read_lines(file)
      rescue IO::Error
        next
      end
      shown = ::Path[file].relative_to(root).to_s
      open = false
      lines.each_with_index do |line, index|
        if head = spec_block_head(line)
          blocks << SpecBlock.new(shown, index + 1, head[0], [] of String, head[1])
          open = true
        elsif open && line.rstrip == "end"
          open = false
        elsif open && (reason = spec_todo_reason(line))
          blocks[-1].reasons << reason
        end
      end
    end
    blocks
  end

  # `spec 1.5  # label` at a line's start -> {"1.5", "label"}.
  private def spec_block_head(line : String) : {String, String?}?
    return nil unless line.starts_with?("spec ")
    rest = line[5..]
    number = rest.split.first? || return nil
    return nil unless spec_number?(number, chapter_ok: false)
    after = rest[number.size..]
    return {number, nil} if after.blank?
    return nil unless after[0].whitespace?
    after = after.lstrip
    return nil unless after.starts_with?('#')
    {number, after[1..].split.join(" ").presence}
  end

  # The line a block's head should be (5.15): `spec N.M  # clause text`,
  # the text cut at the last whole word that fits 80 columns, then `…`.
  private def spec_label_line(number : String, text : String) : String
    head = "spec #{number}  # "
    full = head + text
    return full if full.size <= 80
    line = head
    text.split(' ').each_with_index do |word, index|
      candidate = index == 0 ? line + word : "#{line} #{word}"
      break if candidate.size + 1 > 80
      line = candidate
    end
    line + "…"
  end

  # ROOT/.spec.lock (5.10): `N.M HASH` per reviewed clause.
  private def spec_lock_of(root : String) : Hash(String, String)
    lock = {} of String => String
    file = File.join(root, ".spec.lock")
    return lock unless File.file?(file)
    @spec_nospec.clear
    File.read_lines(file).each_with_index do |line, index|
      next if line.blank?
      parts = line.split
      if parts.first? == "nospec" && parts.size >= 2
        @spec_nospec[parts[1]] = parts[2..].to_set
        next
      end
      unless parts.size == 2 && spec_number?(parts[0], chapter_ok: false) && parts[1].size == 8
        raise SpecError.new(".spec.lock:#{index + 1}: a line is `N.M HASH`, not '#{line}'; " \
                            "`#{Command.program_name} spec ack N.M` writes it")
      end
      lock[parts[0]] = parts[1]
    end
    lock
  end

  # Writes *lock* sorted, dropping lines for clauses the spec no longer has.
  private def spec_lock_write(root : String, lock : Hash(String, String),
                              clauses : Array(SpecClause)) : Nil
    known = clauses.map(&.number).to_set
    lock.each_key { |number| puts "removed: #{number}" unless known.includes?(number) }
    lines = lock.select { |number, _| known.includes?(number) }.to_a.sort_by! do |number, _|
      spec_sort_key(number)
    end
    text = lines.map { |number, hash| "#{number} #{hash}\n" }.join
    @spec_nospec.to_a.sort_by!(&.[0]).each do |path, names|
      text += (["nospec", path] + names.to_a.sort!).join(" ") + "\n"
    end
    File.write(File.join(root, ".spec.lock"), text)
  end

  # The indexes of the leading comment block: after a `#!` line and blank
  # lines, the consecutive lines starting with `#`.
  private def spec_leading_block(lines : Array(String)) : Array(Int32)
    index = 0
    index += 1 if lines.first?.try(&.starts_with?("#!"))
    while index < lines.size && lines[index].blank?
      index += 1
    end
    block = [] of Int32
    while index < lines.size && lines[index].lstrip.starts_with?('#')
      block << index
      index += 1
    end
    block
  end

  # What follows `# spec:` on a tag line, or nil when it is no tag line.
  private def spec_tag_rest(line : String) : String?
    stripped = line.lstrip
    return nil unless stripped.starts_with?('#')
    body = stripped[1..].lstrip
    return nil unless body.starts_with?("spec:")
    body[5..].strip
  end

  private def spec_parse_tag(test : SpecTest, rest : String, site : String) : Nil
    if rest.starts_with?("none")
      reason = rest[4..].strip
      unless reason.size > 2 && reason.starts_with?('(') && reason.ends_with?(')') && test.items.empty?
        raise SpecError.new("#{site}: `# spec: none` takes a reason in parentheses and stands alone: " \
                            "`# spec: none (implementation test: why)`")
      end
      test.none = reason[1..-2].strip
      return
    end
    if test.none
      raise SpecError.new("#{site}: this file said `# spec: none`; a test naming clauses drops that line")
    end
    rest.split(',').each do |raw|
      item = raw.strip
      number, at, version = item.partition('@')
      ok = spec_number?(number, chapter_ok: false) &&
           (at.empty? || (version.size == 8 && version.each_char.all? { |c| c.ascii_number? || c.in?('a'..'f') }))
      unless ok
        raise SpecError.new("#{site}: `# spec:` takes N.M@VERSION items (VERSION: 8 hex digits, `#{Command.program_name} " \
                            "spec ack N.M` writes it) or none (reason), not '#{item}'")
      end
      test.items << {number, at.empty? ? nil : version}
    end
  end

  # Every `SPEC N.M` in a comment, not `iyi SPEC N.M` nor `SPEC N.M.K`.
  private def spec_prose_numbers(text : String) : Array(String)
    numbers = [] of String
    from = 0
    while at = text.index("SPEC ", from)
      from = at + 5
      next if at > 0 && text[at - 1].ascii_alphanumeric?
      next if at >= 4 && text[(at - 4)...at] == "iyi "
      major = text[from..].each_char.take_while(&.ascii_number?).join
      next if major.empty? || text[from + major.size]? != '.'
      after = from + major.size + 1
      minor = text[after..].each_char.take_while(&.ascii_number?).join
      next if minor.empty?
      tail = after + minor.size
      next if text[tail]?.try(&.ascii_alphanumeric?)
      next if text[tail]? == '.' && text[tail + 1]?.try(&.ascii_number?)
      numbers << "#{major}.#{minor}"
    end
    numbers
  end

  # `todo "reason"` or `todo("reason")` at a line's start.
  private def spec_todo_reason(line : String) : String?
    stripped = line.lstrip
    return nil unless stripped.starts_with?("todo")
    rest = stripped[4..].lstrip.lstrip('(').lstrip
    return nil unless rest.starts_with?('"')
    close = rest.rindex('"')
    return nil unless close && close > 0
    raw = rest[1...close]
    String.build do |io|
      escaped = false
      raw.each_char do |char|
        if escaped
          io << '\\' unless char.in?('"', '\\')
          io << char
          escaped = false
        elsif char == '\\'
          escaped = true
        else
          io << char
        end
      end
      io << '\\' if escaped
    end
  end

  private def spec_changelog(root : String) : Array(SpecEntry)
    file = File.join(root, "CHANGELOG.md")
    return [] of SpecEntry unless File.file?(file)
    entries = [] of SpecEntry
    heading = nil
    versions = [] of String
    File.each_line(file) do |line|
      # `## DATE` or, under a release's `## 0.2.0`, `### DATE`.
      level = line.starts_with?("### ") ? 4 : line.starts_with?("## ") ? 3 : 0
      if level > 0 && spec_dated?(line[level..])
        entries << SpecEntry.new(heading, versions) if heading
        heading = line[level..].strip
        versions = [] of String
      elsif level > 0
        # A release heading ends the entry above it.
        entries << SpecEntry.new(heading, versions) if heading
        heading = nil
        versions = [] of String
      end
      spec_version_tokens(line, versions) if heading
    end
    entries << SpecEntry.new(heading, versions) if heading
    entries
  end

  private def spec_dated?(text : String) : Bool
    text.size >= 10 && text[4] == '-' && text[7] == '-' &&
      {0, 1, 2, 3, 5, 6, 8, 9}.all? { |i| text[i].ascii_number? }
  end

  # Each `N.M@hhhhhhhh` in *line*, as "N.M@hhhhhhhh".
  private def spec_version_tokens(line : String, into : Array(String)) : Nil
    from = 0
    while at = line.index('@', from)
      from = at + 1
      start = at
      while start > 0 && (line[start - 1].ascii_alphanumeric? || line[start - 1].in?('.', '/', '_'))
        start -= 1
      end
      number = line[start...at]
      next unless spec_number?(number, chapter_ok: false)
      version = line[(at + 1)..].each_char.take_while { |c| c.ascii_number? || c.in?('a'..'f') }.join
      next unless version.size == 8
      into << "#{number}@#{version}"
    end
  end

  # --- reports -------------------------------------------------------------

  # A clause's files and status, worst first.
  # ris: a .spec.lock line decides review (5.10, 5.14): with one, the
  # tags' `@V` is ignored; without one, a block is not reviewed yet and a
  # tag's `@V` decides as before.
  private def spec_status(clause : SpecClause, tests : Array(SpecTest)) : {String, Array(SpecTest)}
    marker = @spec_markers[clause.number]?
    files = tests.select { |test| test.names?(clause.number) && (!marker || test.tagged) }
    named = spec_blocks_naming(clause)
    versions = files.flat_map { |test| test.items.select { |item| item[0] == clause.number }.map(&.[1]) }
    todo = files.all?(&.todo) && named.all?(&.todo)
    locked = @spec_lock[clause.number]?
    status =
      if files.empty? && named.empty? && !marker
        "uncovered"
      elsif locked
        locked != clause.version ? "to review" : todo ? "todo" : "ok"
      elsif !named.empty? || versions.any? { |version| version && version != clause.version }
        "to review"
      elsif versions.any?(&.nil?)
        "unversioned"
      elsif todo
        "todo"
      else
        "ok"
      end
    {status, files}
  end

  private def spec_blocks_naming(clause : SpecClause) : Array(SpecBlock)
    @spec_blocks.select { |block| block.number == clause.number }
  end

  private def spec_reasons(clause : SpecClause, tests : Array(SpecTest)) : Array(String)
    reasons = spec_blocks_naming(clause).flat_map(&.reasons)
    tests.each do |test|
      if test.names?(clause.number) && (reason = test.todo)
        reasons << reason
      end
    end
    if marker = @spec_markers[clause.number]?
      reasons.unshift(marker[2])
    end
    reasons
  end

  private SPEC_STATUSES = ["ok", "todo", "to review", "uncovered", "unversioned"]

  private def spec_report(clauses : Array(SpecClause), tests : Array(SpecTest), json : Bool) : Nil
    rows = clauses.map { |clause| {clause, *spec_status(clause, tests)} }
    counts = SPEC_STATUSES.to_h { |status| {status, rows.count { |row| row[1] == status }} }
    tagged = tests.count { |test| !test.items.empty? || test.none }
    untagged = tests.select { |test| test.items.empty? && test.none.nil? }
    if json
      JSON.build(STDOUT) do |builder|
        builder.object do
          builder.field "clauses" do
            builder.array do
              rows.each do |clause, status, files|
                builder.object do
                  builder.field "number", clause.number
                  builder.field "version", clause.version
                  builder.field "status", status
                  builder.field "text", clause.text
                  builder.field "todo", spec_reasons(clause, tests)
                  if marker = @spec_markers[clause.number]?
                    builder.field "marker", marker[2]
                  end
                  builder.field "files" { spec_files_json(builder, clause, files) }
                end
              end
            end
          end
          builder.field "untagged" { builder.array { untagged.each { |test| builder.scalar test.path } } }
          builder.field "counts" do
            builder.object do
              counts.each { |status, count| builder.field status, count }
              builder.field "tagged_files", tagged
              builder.field "untagged_files", untagged.size
            end
          end
        end
      end
      puts
      return
    end
    rows.each do |clause, status, files|
      proofs = files.size + spec_blocks_naming(clause).size
      head = "#{clause.number.ljust(6)}#{status.ljust(12)}#{proofs.to_s.rjust(3)}  "
      room = 80 - head.size
      words = clause.text.size > room ? clause.text[0, room - 1] + "…" : clause.text
      puts head + words
    end
    puts spec_summary(clauses.size, counts, tagged, untagged.size)
  end

  private def spec_summary(total : Int32, counts : Hash(String, Int32), tagged : Int32, untagged : Int32) : String
    "#{total} clauses: #{counts["ok"]} ok, #{counts["todo"]} todo, #{counts["to review"]} to review, " \
    "#{counts["uncovered"]} uncovered, #{counts["unversioned"]} unversioned; " \
    "#{tagged} tagged files, #{untagged} untagged"
  end

  private def spec_files_json(builder : JSON::Builder, clause : SpecClause, files : Array(SpecTest)) : Nil
    builder.array do
      files.each do |test|
        builder.object do
          builder.field "file", test.path
          builder.field "version", test.items.find { |item| item[0] == clause.number }.try(&.[1])
          builder.field "todo", test.todo
          builder.field "own", test.items.size == 1
        end
      end
      spec_blocks_naming(clause).each do |block|
        builder.object do
          builder.field "file", "#{block.path}:#{block.line}"
          builder.field "block", true
          builder.field "todo", block.reasons
        end
      end
    end
  end

  private def spec_show(root : String, clauses : Array(SpecClause), tests : Array(SpecTest),
                        target : String, json : Bool) : Nil
    chosen = clauses.select { |clause| spec_selected?(clause, target) }
    if chosen.empty?
      abort! "spec: #{target} is no clause or chapter of the spec; `#{Command.program_name} spec` lists them", :USAGE_ERROR
    end
    entries = spec_changelog(root)
    if json
      JSON.build(STDOUT) do |builder|
        builder.object do
          builder.field "clauses" do
            builder.array do
              chosen.each do |clause|
                status, files = spec_status(clause, tests)
                builder.object do
                  builder.field "number", clause.number
                  builder.field "version", clause.version
                  builder.field "status", status
                  builder.field "text", clause.text
                  builder.field "todo", spec_reasons(clause, tests)
                  if marker = @spec_markers[clause.number]?
                    builder.field "marker", marker[2]
                  end
                  builder.field "history" do
                    builder.array do
                      spec_history(entries, clause).each { |entry| builder.scalar entry.heading }
                    end
                  end
                  builder.field "files" { spec_files_json(builder, clause, files) }
                end
              end
            end
          end
        end
      end
      puts
      return
    end
    chosen.each_with_index do |clause, index|
      puts if index > 0
      status, files = spec_status(clause, tests)
      puts "#{clause.number}@#{clause.version} #{clause.text}"
      puts "  status: #{status}"
      if marker = @spec_markers[clause.number]?
        puts "  marker: #{marker[0]}:#{marker[1]}"
      end
      spec_history(entries, clause).each { |entry| puts "  changelog: #{entry.heading}" }
      files.each do |test|
        version = test.items.find { |item| item[0] == clause.number }.try(&.[1])
        state = version.nil? ? "unversioned" : version == clause.version ? "current" : "to review (#{version})"
        kind = test.items.size == 1 ? "own" : "shared"
        todo = test.todo ? ", todo: #{test.todo}" : ""
        puts "  test: #{test.path} (#{kind}, #{state}#{todo})"
      end
      spec_blocks_naming(clause).each do |block|
        puts "  block: #{block.path}:#{block.line}#{block.todo ? " (todo)" : ""}"
      end
      if locked = @spec_lock[clause.number]?
        puts "  .spec.lock: #{locked}#{locked == clause.version ? "" : " (to review)"}"
      end
    end
  end

  private def spec_history(entries : Array(SpecEntry), clause : SpecClause) : Array(SpecEntry)
    entries.select { |entry| entry.versions.any?(&.starts_with?("#{clause.number}@")) }
  end

  # `ris spec ack N[.M]`: .spec.lock takes the clause's current hash
  # (5.10) and drops lines for clauses the spec no longer has; every tag
  # item naming it takes its current version too; a prose-only file citing
  # it gets a tag line naming every clause its prose names.
  # `ris spec ack --from-tags` locks each clause whose versioned tags all
  # match it, so a project moves from tags to .spec.lock.
  private def spec_ack : NoReturn
    target = options.shift?
    if target == "--nospec"
      spec_ack_nospec
    end
    if target == "--from-tags" && options.empty?
      root, clauses, tests = spec_load_or_abort
      lock = @spec_lock.dup
      seeded = 0
      clauses.each do |clause|
        versions = tests.flat_map { |test| test.items.select { |item| item[0] == clause.number }.map(&.[1]) }.compact
        next if versions.empty? || versions.any? { |version| version != clause.version }
        next if lock[clause.number]? == clause.version
        lock[clause.number] = clause.version
        seeded += 1
      end
      spec_lock_write(root, lock, clauses)
      puts ".spec.lock: #{seeded} clause#{seeded == 1 ? "" : "s"} locked from tags"
      exit
    end
    unless target && spec_target?(target) && options.empty?
      abort! "spec ack takes one clause or chapter: `#{Command.program_name} spec ack 1.3` or `ack 1`; " \
             "`ack --from-tags` locks the clauses whose tags match", :USAGE_ERROR
    end
    root, clauses, tests = spec_load_or_abort
    chosen = clauses.select { |clause| spec_selected?(clause, target) }
    if chosen.empty?
      abort! "spec ack: #{target} is no clause or chapter of the spec; `#{Command.program_name} spec` lists them", :USAGE_ERROR
    end
    current = chosen.to_h { |clause| {clause.number, clause.version} }
    lock = @spec_lock.dup
    chosen.each do |clause|
      next if spec_status(clause, tests)[0] == "uncovered"
      lock[clause.number] = clause.version
      puts ".spec.lock: #{clause.number} #{clause.version}"
    end
    spec_lock_write(root, lock, clauses)
    written = 0
    tests.each do |test|
      next unless test.items.any? { |item| current[item[0]]? && item[1] != current[item[0]] }
      path = File.join(root, test.path)
      lines = File.read_lines(path, chomp: false)
      items = test.items.map { |item| current[item[0]]? ? "#{item[0]}@#{current[item[0]]}" : (item[1] ? "#{item[0]}@#{item[1]}" : item[0]) }
      if test.tagged
        tag_lines = spec_leading_block(lines.map(&.chomp)).select { |index| spec_tag_rest(lines[index]) }
        first = tag_lines.first
        indent = lines[first][0, lines[first].size - lines[first].lstrip.size]
        tag_lines.reverse_each { |index| lines.delete_at(index) unless index == first }
        lines[first] = "#{indent}# spec: #{items.join(", ")}\n"
      else
        at = lines.first?.try(&.starts_with?("#!")) ? 1 : 0
        lines.insert(at, "# spec: #{items.join(", ")}\n")
      end
      File.write(path, lines.join)
      puts "acked #{test.path}: #{items.join(", ")}"
      written += 1
    end
    puts "#{written} file#{written == 1 ? "" : "s"} acked for #{target}"
    exit
  end

  # ris: `ris check --fix`'s spec step writes a missing clause label and
  # refreshes a stale one (5.15). It never touches .spec.lock: a label is
  # not a review.
  private def spec_fix_labels(root : String, clauses : Array(SpecClause)) : Nil
    by_number = clauses.to_h { |clause| {clause.number, clause} }
    @spec_blocks.group_by(&.path).each do |path, blocks|
      file = File.join(root, path)
      lines = File.read_lines(file, chomp: false)
      changed = false
      blocks.each do |block|
        clause = by_number[block.number]? || next
        next if spec_label_ok?(block, clause)
        lines[block.line - 1] = spec_label_line(clause.number, clause.text) + "\n"
        changed = true
      end
      next unless changed
      File.write(file, lines.join)
      puts "labelled #{path}"
    end
    @spec_blocks = spec_blocks_of(root)
  end

  # A label matches the clause text, whole or cut as spec_label_line cuts it.
  private def spec_label_ok?(block : SpecBlock, clause : SpecClause) : Bool
    return block.label.nil? if spec_owner?(block)
    label = block.label || return false
    head = "spec #{clause.number}  # "
    label == clause.text || label == spec_label_line(clause.number, clause.text)[head.size..]
  end

  # `ris check spec` (SPEC 6.8): every failure with its next command,
  # then the counts. Unversioned and untagged files are reported only.
  private def spec_check(fix = false) : NoReturn
    name = Command.program_name
    root, clauses, tests = spec_load_or_abort(spec_root || Dir.current)
    if clauses.empty?
      STDERR.puts <<-FORM
        no spec: write SPEC.md with a clause
          * 1.1 TEXT
        and prove it at the end of the root module
          spec 1.1
            EXPR == VALUE
          end
        FORM
      exit 1
    end
    spec_fix_labels(root, clauses) if fix
    proofless = spec_proofless(root)
    by_number = clauses.to_h { |clause| {clause.number, clause} }
    recorded = spec_changelog(root).flat_map(&.versions).to_set
    failures = [] of {String, String}
    if File.file?(File.join(root, "spec.lock"))
      failures << {"spec.lock is the old name of .spec.lock",
                   "rename it: `git mv spec.lock .spec.lock`"}
    end
    if File.file?(File.join(root, "SPEC_CHANGELOG.md"))
      failures << {"SPEC_CHANGELOG.md is the old name: the spec's changes are the changelog",
                   "move its entries into CHANGELOG.md (`###` under a release heading), then delete it"}
    end
    spec_drift_failures(root, failures)
    tests.each do |test|
      next unless test.tagged
      test.items.each do |number, _|
        next if by_number[number]?
        failures << {"#{test.path} names #{number}, which is no clause of the spec",
                     "name a clause `#{name} spec` lists, or drop #{number} from the tag"}
      end
    end
    @spec_blocks.each do |block|
      site = "#{block.path}:#{block.line}"
      unless clause = by_number[block.number]?
        failures << {"#{site}: spec #{block.number} names no clause of the spec",
                     "name a clause `#{name} spec` lists"}
        next
      end
      if block.number == "8.1"
        lines = File.read_lines(File.join(root, block.path))
        header = spec_leading_block(lines)
        unless header.any? { |i| lines[i].starts_with?("# standard: ") && !lines[i][12..].blank? }
          failures << {"#{site}: name the standard",
                       "add `# standard: ...` to the module header"}
        end
      end
      if block.label && !spec_label_ok?(block, clause)
        failures << {"the label of spec #{block.number} at #{site} differs from SPEC.md",
                     "run `#{name} check --fix`"}
      end
    end
    @spec_lock.each_key do |number|
      next if by_number[number]?
      failures << {".spec.lock holds #{number}, which is no clause of the spec",
                   "any `#{name} spec ack` drops the line"}
    end
    clauses.each do |clause|
      status, files = spec_status(clause, tests)
      if marker = @spec_markers[clause.number]?
        site = "#{marker[0]}:#{marker[1]}"
        spec_blocks_naming(clause).each do |block|
          message = block.todo ? "the block holds the todo; remove the marker" : "#{clause.number} is proven by #{block.path}:#{block.line}; remove its todo marker"
          failures << {"#{site}: #{message}", "keep the todo or proof in its module"}
        end
        tests.select { |test| test.tagged && test.names?(clause.number) }.each do |test|
          message = test.todo ? "the test holds the todo; remove the marker" : "#{clause.number} is proven by #{test.path}:#{test.tag_lines[clause.number]}; remove its todo marker"
          failures << {"#{site}: #{message}", "keep the todo or proof in its test"}
        end
      end
      if status == "to review"
        locked = @spec_lock[clause.number]?
        blocks = spec_blocks_naming(clause)
        if locked || !blocks.empty?
          sites = blocks.map { |block| "#{block.path}:#{block.line}" } + files.map(&.path)
          what = locked ? "changed since its proofs were reviewed" : "has proofs not reviewed yet"
          failures << {"#{clause.number} #{what}",
                       "review #{sites.join(", ")}, then `#{name} spec ack #{clause.number}`"}
        else
          files.each do |test|
            test.items.each do |number, version|
              next unless number == clause.number && version && version != clause.version
              failures << {"#{clause.number}: #{test.path} tag holds #{version}, clause is now #{clause.version}",
                           "review the test against `#{name} spec #{clause.number}`, then `#{name} spec ack #{clause.number}`"}
            end
          end
        end
      end
      unless spec_module_id?(clause.number.rpartition('.')[0]) || recorded.includes?("#{clause.number}@#{clause.version}")
        failures << {"#{clause.number}: no CHANGELOG.md entry records #{clause.number}@#{clause.version}",
                     "add `## #{Time.local.to_s("%Y-%m-%d")} · #{clause.number}@#{clause.version}` to CHANGELOG.md with the reason"}
      end
      if status == "uncovered"
        failures << {"#{clause.number} has no proof",
                     "add `spec #{clause.number}` at the end of the module that keeps it"}
      end
    end
    failures.each do |failure, step|
      puts failure
      puts "  next: #{step}"
    end
    proofless.each { |text| STDERR.puts text }
    counts = SPEC_STATUSES.to_h { |status| {status, clauses.count { |clause| spec_status(clause, tests)[0] == status }} }
    tagged = tests.count { |test| !test.items.empty? || test.none }
    puts spec_summary(clauses.size, counts, tagged, tests.size - tagged)
    exit failures.empty? && proofless.empty? ? 0 : 1
  end

  # `ris spec todo`: the promises not kept yet, one todo test a line.
  private def spec_todo : NoReturn
    json = false
    while option = options.shift?
      abort! "spec todo takes only --json, not '#{option}'", :USAGE_ERROR unless option == "--json"
      json = true
    end
    root, clauses, tests = spec_load_or_abort
    todos = tests.select(&.todo)
    blocks = @spec_blocks.reject(&.reasons.empty?)
    markers = clauses.select { |clause| @spec_markers.has_key?(clause.number) }
    if json
      JSON.build(STDOUT) do |builder|
        builder.object do
          builder.field "todo" do
            builder.array do
              markers.each do |clause|
                marker = @spec_markers[clause.number]
                builder.object do
                  builder.field "clauses" { builder.array { builder.scalar clause.number } }
                  builder.field "file", "#{marker[0]}:#{marker[1]}"
                  builder.field "reason", marker[2]
                end
              end
              blocks.each do |block|
                block.reasons.each do |reason|
                  builder.object do
                    builder.field "clauses", [block.number]
                    builder.field "file", "#{block.path}:#{block.line}"
                    builder.field "reason", reason
                  end
                end
              end
              todos.each do |test|
                builder.object do
                  builder.field "clauses" { builder.array { test.items.each { |item| builder.scalar item[0] } } }
                  builder.field "file", test.path
                  builder.field "reason", test.todo
                end
              end
            end
          end
        end
      end
      puts
    else
      markers.each do |clause|
        marker = @spec_markers[clause.number]
        puts "#{marker[0]}:#{marker[1]} #{clause.number} #{marker[2]}"
      end
      todos.each do |test|
        clauses = test.items.empty? ? "-" : test.items.map(&.[0]).join(",")
        puts "#{clauses.ljust(10)}#{test.path}: #{test.todo}"
      end
      blocks.each do |block|
        block.reasons.each do |reason|
          puts "#{block.path}:#{block.line} #{block.number} #{reason}"
        end
      end
      total = todos.size + markers.size + blocks.sum(&.reasons.size)
      puts "#{total} todo test#{total == 1 ? "" : "s"}"
      marks = spec_scan_defs(root).flat_map do |scan|
        whole = scan.module_mark.try do |line|
          SpecMark.new(scan.path, line, scan.module_reason, true, @spec_nospec[scan.path]?.try(&.size) || 0)
        end
        whole ? [whole] + scan.marks : scan.marks
      end
      marks.each do |mark|
        puts "#{mark.path}:#{mark.line} NoSpec #{mark.whole ? "module" : "def"}, " \
             "#{mark.count} def#{mark.count == 1 ? "" : "s"}: #{mark.reason}"
      end
      count = marks.sum(&.count)
      puts "#{marks.size} NoSpec mark#{marks.size == 1 ? "" : "s"} over #{count} def#{count == 1 ? "" : "s"}" unless marks.empty?
    end
    exit
  end

  # A SPEC change's CHANGELOG entry (2026-11-15 on) names its draft
  # folder, which must hold the drift report (AGENTS.md: EGM is required).
  private SPEC_DRIFT_SINCE = "2026-11-15"

  private def spec_drift_failures(root : String, failures : Array({String, String})) : Nil
    file = File.join(root, "CHANGELOG.md")
    return unless File.file?(file)
    date = nil
    seen = Set(String).new
    File.each_line(file) do |line|
      if heading = line.match(/^\#{2,3} (\d{4}-\d\d-\d\d)/)
        date = heading[1]
        next
      end
      next unless date && date >= SPEC_DRIFT_SINCE
      line.scan(/doc\/drafts\/([\w-]+)/) do |found|
        folder = "doc/drafts/#{found[1]}"
        next unless seen.add?(folder)
        dir = File.join(root, folder)
        next if Dir.exists?(dir) && Dir.children(dir).any?(&.ends_with?("_DRIFT_REPORT.md"))
        failures << {"CHANGELOG.md (#{date}) names #{folder}, which has no drift report",
                     "run the EGM drift check and keep it as #{folder}/DATE_DRIFT_REPORT.md"}
      end
    end
  end

  # --- public defs need a proof (SPEC 6.8, doc/drafts/spec-required) -----

  # A def's name, where it is, the type around it (for the hint) and
  # whether it is a file's top-level def.
  private record SpecDef, line : Int32, name : String, owner : String?, top : Bool

  # A `@[NoSpec("reason")]` mark: on a module (*whole*) or a def.
  private record SpecMark, path : String, line : Int32, reason : String,
    whole : Bool, count : Int32

  # One scanned `.ri` file: its public defs, its spec blocks' lines
  # (assertion lines and todo-block lines), its marks and module mark.
  private class SpecDefFile
    getter path : String
    getter defs = [] of SpecDef
    getter proof = [] of String
    getter marks = [] of SpecMark
    getter marked = [] of SpecDef
    getter bad = [] of Int32
    property module_mark : Int32? = nil
    property module_reason = ""

    def initialize(@path : String)
    end
  end

  private SPEC_DEF = /^(\s*)((?:private|protected)\s+)?(?:(?:pub|abstract)\s+)*def\s+(self\.)?([^\s(:]+)/
  private SPEC_OWNER = /^(\s*)(?:(?:private|pub|abstract)\s+)*(?:class|struct|module)\s+([A-Z][\w:]*)/

  private def spec_scan_defs(root : String) : Array(SpecDefFile)
    files = [] of String
    project_walk(root, files, &.downcase.ends_with?(".ri"))
    files.sort!.compact_map do |file|
      lines = begin
        File.read_lines(file)
      rescue IO::Error
        next
      end
      spec_scan_file(::Path[file].relative_to(root).to_s, lines)
    end
  end

  private def spec_scan_file(path : String, lines : Array(String)) : SpecDefFile?
    scan = SpecDefFile.new(path)
    code = lines.each_index.find { |i| !(lines[i].blank? || lines[i].lstrip.starts_with?('#')) }
    if code && lines[code].starts_with?("@[Ffi]")
      return nil
    end
    if code && lines[code].starts_with?("@[NoSpec")
      after = (code + 1...lines.size).find { |i| !(lines[i].blank? || lines[i].lstrip.starts_with?('#')) }
      # A blank line after it makes it the module's even above a def.
      unless after && after == code + 1 && (lines[after] =~ SPEC_DEF || lines[after].lstrip.starts_with?("@["))
        scan.module_mark = code + 1
        scan.module_reason = spec_mark_reason(lines[code]) || ""
        scan.bad << code + 1 if scan.module_reason.blank?
      end
    end
    first_block = lines.index { |line| spec_block_head(line) } || lines.size
    skip_until = nil
    owners = [] of {Int32, String, Bool}
    pending = nil
    ffi = false
    lines.each_with_index do |line, index|
      break if index >= first_block
      if skip_until
        skip_until = nil if line.rstrip == skip_until || line.strip == skip_until
        next
      end
      if heredoc = line.match(/<<[-~]([A-Z_]+)/)
        skip_until = heredoc[1]
        next
      end
      if opener = line.match(/^(\s*)(?:(?:pub|private)\s+)?macro\s/)
        skip_until = "#{opener[1]}end"
        next
      end
      stripped = line.lstrip
      next if line.blank? || stripped.starts_with?('#')
      indent = line.size - stripped.size
      while (last = owners.last?) && last[0] >= indent
        owners.pop
      end
      if owner = line.match(SPEC_OWNER)
        owners << {indent, owner[2], ffi}
        pending = nil
        ffi = false
        next
      end
      if stripped.starts_with?("@[")
        ffi = true if stripped.starts_with?("@[Ffi]")
        if stripped.starts_with?("@[NoSpec") && index + 1 != scan.module_mark
          reason = spec_mark_reason(stripped)
          if reason.nil? || reason.blank?
            scan.bad << index + 1
          else
            pending = {index + 1, reason}
          end
        end
        next
      end
      mark = pending
      pending = nil
      ffi = false
      match = line.match(SPEC_DEF) || next
      next if match[2]?
      # An `@[Ffi]` type's defs are the OS's API (R2).
      next if owners.any?(&.[2])
      name = match[4]
      next if name.includes?('{') || name.includes?('%')
      found = SpecDef.new(index + 1, name, owners.last?.try(&.[1]), indent == 0 && owners.empty?)
      if mark
        scan.marks << SpecMark.new(path, mark[0], mark[1], false, 1)
        scan.marked << found
      else
        scan.defs << found
      end
    end
    spec_proof_lines(lines, first_block, scan.proof)
    scan
  end

  # The lines of *lines*' spec blocks that can cover a def (R3): a
  # block's top-level lines that assign nothing, or every line of a block
  # that holds `todo`.
  private def spec_proof_lines(lines : Array(String), from : Int32, into : Array(String)) : Nil
    index = from
    while index < lines.size
      unless spec_block_head(lines[index])
        index += 1
        next
      end
      body = [] of String
      index += 1
      while index < lines.size && lines[index].rstrip != "end"
        body << lines[index]
        index += 1
      end
      if body.any? { |line| spec_todo_reason(line) }
        into.concat(body)
      else
        base = body.find { |line| !line.blank? }.try { |line| line.size - line.lstrip.size }
        body.each do |line|
          next if line.blank? || line.size - line.lstrip.size != base
          next if line.lstrip.matches?(/^[a-z_][\w, ]*\s*[-+*\/|&]?=(?![=~])/)
          into << line
        end
      end
    end
  end

  # The text a NoSpec mark's string holds; nil when it holds no string.
  private def spec_mark_reason(line : String) : String?
    open = line.index('"') || return nil
    close = line.rindex('"') || return nil
    return nil unless close > open
    line[open + 1...close]
  end

  # R3: does a proof line name *found*?
  private def spec_covers?(found : SpecDef, line : String) : Bool
    name = found.name
    return !!(line =~ /\.new(?![\w?!])/) if name == "initialize"
    if name[0].ascii_letter? || name[0] == '_'
      base = Regex.escape(name.rchop('='))
      return true if line =~ /\.#{base}(?![\w?!])/
      return true if found.top && line =~ /(?<![\w.])#{base}\(/
      false
    elsif name.starts_with?("[]")
      line.includes?('[')
    else
      op = name.rchop('@')
      line.includes?(" #{op} ") || line.includes?(".#{op}(") || line.includes?("#{op}(")
    end
  end

  # R4 and R5: the failures, each the text to print.
  private def spec_proofless(root : String) : Array(String)
    out = [] of String
    seen = Set(String).new
    spec_scan_defs(root).each do |scan|
      seen << scan.path if scan.module_mark
      scan.bad.each do |line|
        out << "#{scan.path}:#{line}: NoSpec needs a reason: " \
               "write `@[NoSpec(\"why no proof\")]`"
      end
      recorded = @spec_nospec[scan.path]?
      if scan.module_mark && recorded.nil?
        out << "#{scan.path}:#{scan.module_mark}: the module's NoSpec mark is " \
               "not recorded; run `#{Command.program_name} spec ack --nospec #{scan.path}`"
        next
      end
      scan.defs.each do |found|
        next if scan.proof.any? { |line| spec_covers?(found, line) }
        next if recorded && scan.module_mark && recorded.includes?(found.name)
        call = found.top ? "#{found.name}(\"...\")" : "#{found.owner || "Module"}.#{found.name}(\"...\")"
        call = "#{found.owner || "Type"}.new(\"...\")" if found.name == "initialize"
        later = scan.module_mark ? " (added after the module's NoSpec)" : ""
        out << "#{scan.path}:#{found.line}: public def #{found.name} has no proof#{later}; add at the end\n" \
               "  spec N.M\n" \
               "    #{call} == \"...\"\n" \
               "  end\n" \
               "or `todo \"reason\"` inside it, `@[NoSpec(\"reason\")]`, or private"
      end
    end
    @spec_nospec.each_key do |path|
      next if seen.includes?(path)
      out << ".spec.lock: nospec #{path} names no module with a NoSpec mark; " \
             "run `#{Command.program_name} spec ack --nospec #{path}`"
    end
    out
  end

  # `ris spec ack --nospec MODULE...`: .spec.lock records the public defs
  # each marked module has now (R5); an unmarked module's line goes.
  private def spec_ack_nospec : NoReturn
    if options.empty?
      abort! "spec ack --nospec takes the module files: " \
             "`#{Command.program_name} spec ack --nospec src/post.ri`", :USAGE_ERROR
    end
    root, clauses, _tests = spec_load_or_abort(spec_root || Dir.current)
    scans = spec_scan_defs(root).to_h { |scan| {scan.path, scan} }
    while option = options.shift?
      path = File.file?(option) ? ::Path[File.expand_path(option)].relative_to(root).to_s : option
      scan = scans[path]?
      if scan && scan.module_mark
        names = scan.defs.map(&.name).to_set
        @spec_nospec[path] = names
        puts ".spec.lock: nospec #{path} (#{names.size} def#{names.size == 1 ? "" : "s"})"
      elsif @spec_nospec.delete(path)
        puts ".spec.lock: removed nospec #{path}"
      else
        abort! "spec ack --nospec: #{option} is no module with a NoSpec mark; " \
               "put `@[NoSpec(\"reason\")]` first in it", :USAGE_ERROR
      end
    end
    spec_lock_write(root, @spec_lock.dup, clauses)
    exit
  end

  private def spec_usage : String
    name = Command.program_name
    <<-USAGE
      Usage: #{name} spec [N | N.M | MODULE | MODULE.N] [--json]
             #{name} spec ack N[.M] | MODULE[.N] | --from-tags
             #{name} spec ack --nospec FILE...
             #{name} spec todo [--json]

      Link the spec's clauses (SPEC.md or spec/*.md at the root) to their
      proofs: `spec N.M` blocks in the root's modules, and old files under
      test/ tagged `# spec: N.M@VERSION`. A clause no module keeps may
      carry `  <!-- todo: reason -->` after its text in SPEC.md; the
      marker is coverage, excluded from the version, until a proof lands.

          (none)     one line per clause: status, proofs, first words;
                     then the counts. Status: ok, todo, to review,
                     uncovered, unversioned
          MODULE[.N] a module or its clause; ids follow paths under src/
          N, N.M     that chapter or clause: text, version, changelog
                     entries, the proofs naming it
          ack N[.M]  after reviewing the proofs: .spec.lock takes the
                     clause's version (tags naming it too)
          ack --from-tags
                     lock each clause whose tags all match it
          todo       every todo block, test or marker: clause, file, reason

      `#{name} check spec` fails on an unreviewed clause, a tag, block or
      lock line naming no clause, a root version no CHANGELOG.md entry
      records, a clause with no proof, a stale block label (`#{name}
      check --fix` writes labels), no spec at all, and a public def no
      block in its file proves. `@[NoSpec("reason")]` on a def exempts
      it; first in a module it exempts the defs `ack --nospec MODULE`
      records in .spec.lock.
      USAGE
  end
end

# SHA-256 (FIPS 180-4), for clause versions: the compiler links no
# OpenSSL, and Crystal::Digest has only MD5 and SHA1.
module Iyi::SpecSha256
  K = [
    0x428a2f98_u32, 0x71374491_u32, 0xb5c0fbcf_u32, 0xe9b5dba5_u32, 0x3956c25b_u32, 0x59f111f1_u32,
    0x923f82a4_u32, 0xab1c5ed5_u32, 0xd807aa98_u32, 0x12835b01_u32, 0x243185be_u32, 0x550c7dc3_u32,
    0x72be5d74_u32, 0x80deb1fe_u32, 0x9bdc06a7_u32, 0xc19bf174_u32, 0xe49b69c1_u32, 0xefbe4786_u32,
    0x0fc19dc6_u32, 0x240ca1cc_u32, 0x2de92c6f_u32, 0x4a7484aa_u32, 0x5cb0a9dc_u32, 0x76f988da_u32,
    0x983e5152_u32, 0xa831c66d_u32, 0xb00327c8_u32, 0xbf597fc7_u32, 0xc6e00bf3_u32, 0xd5a79147_u32,
    0x06ca6351_u32, 0x14292967_u32, 0x27b70a85_u32, 0x2e1b2138_u32, 0x4d2c6dfc_u32, 0x53380d13_u32,
    0x650a7354_u32, 0x766a0abb_u32, 0x81c2c92e_u32, 0x92722c85_u32, 0xa2bfe8a1_u32, 0xa81a664b_u32,
    0xc24b8b70_u32, 0xc76c51a3_u32, 0xd192e819_u32, 0xd6990624_u32, 0xf40e3585_u32, 0x106aa070_u32,
    0x19a4c116_u32, 0x1e376c08_u32, 0x2748774c_u32, 0x34b0bcb5_u32, 0x391c0cb3_u32, 0x4ed8aa4a_u32,
    0x5b9cca4f_u32, 0x682e6ff3_u32, 0x748f82ee_u32, 0x78a5636f_u32, 0x84c87814_u32, 0x8cc70208_u32,
    0x90befffa_u32, 0xa4506ceb_u32, 0xbef9a3f7_u32, 0xc67178f2_u32,
  ]

  def self.hexdigest(data : Bytes) : String
    h = [0x6a09e667_u32, 0xbb67ae85_u32, 0x3c6ef372_u32, 0xa54ff53a_u32,
         0x510e527f_u32, 0x9b05688c_u32, 0x1f83d9ab_u32, 0x5be0cd19_u32]
    message = Bytes.new(((data.size + 9 + 63) // 64) * 64)
    data.copy_to(message)
    message[data.size] = 0x80_u8
    bits = data.size.to_u64 * 8
    8.times { |i| message[message.size - 1 - i] = (bits >> (8 * i)).to_u8! }
    w = Array(UInt32).new(64, 0_u32)
    (message.size // 64).times do |block|
      base = block * 64
      16.times do |i|
        o = base + i * 4
        w[i] = (message[o].to_u32 << 24) | (message[o + 1].to_u32 << 16) | (message[o + 2].to_u32 << 8) | message[o + 3].to_u32
      end
      (16...64).each do |i|
        s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
        s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
        w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
      end
      a, b, c, d, e, f, g, hh = h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7]
      64.times do |i|
        s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
        ch = (e & f) ^ (~e & g)
        t1 = hh &+ s1 &+ ch &+ K[i] &+ w[i]
        s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
        maj = (a & b) ^ (a & c) ^ (b & c)
        t2 = s0 &+ maj
        hh = g
        g = f
        f = e
        e = d &+ t1
        d = c
        c = b
        b = a
        a = t1 &+ t2
      end
      h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d
      h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
    end
    h.join { |word| word.to_s(16).rjust(8, '0') }
  end

  private def self.rotr(x : UInt32, n : Int32) : UInt32
    (x >> n) | (x << (32 - n))
  end
end
