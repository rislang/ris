require "../test_helper"
require "../support/tempfile"

def compiler_datapath(*components)
  File.join("test", "compiler", "data", *components)
end
