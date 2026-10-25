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

  it "borrows String call arguments in ris and std-style code" do
    ["ri", "iyi"].each do |extension|
      tape_compile(<<-'CODE', extension)
        def width(text : Str) : Int32
          text.size
        end
        def choose(text : Str) : Int32
          0
        end
        def choose(text : String) : String
          text
        end
        heap = "abc".to_heap + "d".to_heap
        width(heap)
        width(text: heap)
        result : String = choose(heap)
        CODE
    end
  end

  it "borrows nilable String arguments without changing overload priority" do
    ["ri", "iyi"].each do |extension|
      tape_compile(<<-'CODE', extension)
        def width(text : Str?) : Int32
          text ? text.size : 0
        end
        def choose(text : Str?, n : Int64) : String?
          "wrong overload".to_heap
        end
        def choose(text : String?, n : Int64) : String?
          text
        end
        def optional(text : String, present : Bool) : String?
          present ? text : nil
        end
        present = optional("abc".to_heap, true)
        absent = optional("abc".to_heap, false)
        width(present)
        width(absent)
        width(text: present)
        width(text: absent)
        width("abc".to_heap)
        result : String? = choose(present, 1)
        result = choose(text: absent, n: 1)
        CODE
    end
  end

  it "does not borrow nilable String into a non-nilable parameter" do
    expect_raises(Iyi::TypeException) do
      tape_compile(<<-'CODE')
        def optional(text : String?) : String?
          text
        end
        def width(text : Str) : Int32
          text.size
        end
        width(optional(nil))
        CODE
    end
  end

  it "does not borrow nilable String assignments" do
    expect_raises(Iyi::TypeException) do
      tape_compile(<<-'CODE')
        def optional(text : String?) : String?
          text
        end
        view : Str? = optional("abc".to_heap)
        CODE
    end
  end

  it "does not borrow String assignments" do
    expect_raises(Iyi::TypeException) do
      tape_compile(<<-'CODE')
        heap = "abc".to_heap + "d"
        view : Str = heap
        CODE
    end
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

describe "ris String parameter retention" do
  it "refuses a read-only String parameter" do
    expect_raises(Iyi::TypeException,
      /name : String is only read; take it as Str/) do
      tape_compile(<<-'CODE')
        def width(name : String) : Int32
          name.size
        end
        width("hello")
        CODE
    end
  end

  it "refuses a read-only nilable String parameter" do
    expect_raises(Iyi::TypeException,
      /name : String\? is only read; take it as Str\?/) do
      tape_compile(<<-'CODE')
        def width(name : String?) : Int32
          name ? name.size : 0
        end
        width(nil)
        CODE
    end
  end

  it "follows a read-only user callee" do
    expect_raises(Iyi::TypeException, /is only read; take it as Str/) do
      tape_compile(<<-'CODE')
        def width(name : String) : Int32
          name.size
        end
        def forwarded(name : String) : Int32
          width(name)
        end
        forwarded("hello")
        CODE
    end
  end

  it "allows an alias returned from a parameter" do
    tape_compile(<<-'CODE')
      def retained(name : String) : String
        alias_name = name
        alias_name
      end
      retained("hello")
      CODE
  end

  it "leaves other union and generic restrictions alone" do
    tape_compile(<<-'CODE')
      def width(name : String | Int32, names : Array(String)) : Int32
        names.size
      end
      width(1, ["hello"])
      CODE
  end
end
