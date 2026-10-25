require "./spec_helper"

private def tape_compile(code : String, extension = "ri")
  compiler = create_spec_compiler
  compiler.prelude = "iyi/prelude"
  compiler.no_codegen = true
  source = Iyi::Compiler::Source.new(
    File.expand_path("text-default.#{extension}"), code)
  compiler.compile(source, File.expand_path("text-default"))
end

describe "ris tape text" do
  it "types literals and interpolation as Str" do
    tape_compile(<<-'CODE')
      def text(value : Str) : Str
        value
      end
      text("literal")
      text("number #{42}")
      CODE
  end

  it "keeps iyi literals as String" do
    tape_compile(<<-'CODE', "iyi")
      def text(value : String) : String
        value
      end
      text("literal")
      CODE
  end

  it "requires an explicit heap copy for typed arguments" do
    expect_raises(Iyi::TypeException, /\.to_heap/) do
      tape_compile(<<-'CODE')
        def text(value : String) : String
          value
        end
        text("literal")
        CODE
    end
  end

  it "rejects tape constants" do
    expect_raises(Iyi::TypeException, /\.to_heap/) do
      tape_compile("TEXT = \"literal\"\nputs TEXT")
    end
  end

  it "keeps explicit static retention as String" do
    tape_compile(<<-'CODE')
      def text(value : String) : String
        value
      end
      text("literal".to_heap)
      CODE
  end

  it "accepts explicit retained text" do
    tape_compile(<<-'CODE')
      class Kept
        @text : String
        def initialize
          @text = "number #{42}".to_heap
        end
      end
      Kept.new
      CODE
  end
end
