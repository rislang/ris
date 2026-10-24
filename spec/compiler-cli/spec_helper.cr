require "spec"
require "./support/expectations"
require "../support/tempfile"

# The binaries by the names the build gives them: `crystal.exe` on Windows.
# Without the suffix a process still starts - Windows adds it when it looks
# a command up - but a spec that asks whether the file is there before it
# runs anything was told no, and the bind pipeline never ran on Windows.
EXE_SUFFIX = {{ flag?(:win32) ? ".exe" : "" }}

CRYSTAL_BIN = ENV.fetch("CRYSTAL_SPEC_COMPILER_BIN") { Path[Dir.current, ".build", "crystal#{EXE_SUFFIX}"].to_s }

# The built `crystal` looks for its library in `share/crystal/src` beside
# `.build`, where an install puts it; a checkout has it in `src`, as
# `bin/crystal` says. Without it no build finds even the empty prelude.
ENV["CRYSTAL_PATH"] ||= "lib#{Process::PATH_DELIMITER}#{File.expand_path("../../src", __DIR__)}"

def crystal
  CRYSTAL_BIN
end

# iyi: the compiler under its own name. Its own binary because its command
# surface is its own — and, for the daemon, because a server is the compiler it
# was built from.
IYI_BIN = ENV.fetch("IYI_SPEC_COMPILER_BIN") { Path[Dir.current, ".build", "iyi#{EXE_SUFFIX}"].to_s }

def iyi
  IYI_BIN
end

def fixture_path(name : String)
  File.expand_path(File.join(__DIR__, "fixtures", name))
end
