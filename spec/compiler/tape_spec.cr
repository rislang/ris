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
        text("value #{42}")
        CODE
    end
  end

  it "rejects tape constants" do
    expect_raises(Iyi::TypeException, /\.to_heap/) do
      tape_compile(<<-'CODE')
        TEXT = "value #{42}"
        puts TEXT
        CODE
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
  it "uses static String in heap places" do
    tape_compile(<<-'CODE')
      TEXT = ("constant")
      USERS = {42 => "alice"}
      class User
        @title : String = "Welcome"
        @optional : String? = "static"
        @@title : String = "Class"
        def initialize(@name : String)
          @title = "Again"
        end
      end
      User.new(name: "carol")
      list = [("a"), "b"]
      list << "x"
      hash = {"k" => "v"}
      hash["k"] = "updated"
      puts({"tuple", 42}, {name: "named"}, TEXT, USERS)
      CODE
  end

  it "prefers the Str overload before trying String" do
    tape_compile(<<-'CODE')
      def choose(text : Str) : Int32
        1
      end
      def choose(text : String) : String
        text
      end
      result : Int32 = choose("literal")
      def choose(text : Str, n : Int64) : Int32
        1
      end
      def choose(text : String, n : Int64) : String
        text
      end
      result = choose("literal", 1)
      CODE
  end

  it "does not carry literal provenance through locals" do
    expect_raises(Iyi::TypeException, /name holds tape text/) do
      tape_compile(<<-'CODE')
        class User
          @name : String
          def initialize
            name = "alice"
            @name = name
          end
        end
        User.new
        CODE
    end
  end

end
