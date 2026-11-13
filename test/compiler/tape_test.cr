require "./test_helper"

private def tape_compile(code : String, extension = "ri")
  compiler = create_spec_compiler
  compiler.prelude = "ris/prelude"
  compiler.no_codegen = true
  source = Iyi::Compiler::Source.new(
    File.expand_path("text-default.#{extension}"), code)
  compiler.compile(source, File.expand_path("text-default"))
end

describe "ris tape text" do
  it "types literals and interpolation as String" do
    tape_compile(<<-'CODE')
      def text(value : String) : String
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

  it "builds tape constants on the program tape" do
    tape_compile(<<-'CODE')
      TEXT = "value #{42}"
      puts TEXT
      CODE
  end

  it "builds a class variable's array on the program tape, as a constant's" do
    tape_compile(<<-'CODE')
      LIST = [1, 2, 4]
      class Foo
        @@var = [1, 2, 4]
        def self.var
          @@var
        end
      end
      puts Foo.var.size + LIST.size
      CODE
  end

  it "accepts an explicit deep program copy" do
    tape_compile(<<-'CODE')
      @[OnTape]
      struct Saved
        getter text : String
        def initialize(@text)
        end
      end
      class State
        @@saved : Saved? = nil
        def self.keep(text : String)
          @@saved = Saved.new(text).copy_to(Program.tape)
        end
      end
      tape { State.keep("request #{42}") }
      CODE
  end

  it "keeps explicit static retention as String" do
    tape_compile(<<-'CODE')
      def text(value : String) : String
        value
      end
      text("literal")
      CODE
  end

  it "accepts explicit retained text" do
    tape_compile(<<-'CODE')
      class Kept
        @text : String
        def initialize
          @text = "number #{42}"
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

  it "borrows String call arguments in ris and std-style code" do
    ["ri", "iyi"].each do |extension|
      tape_compile(<<-'CODE', extension)
        def width(text : String) : Int32
          text.size
        end
        heap = "abc" + "d"
        width(heap)
        width(text: heap)
        CODE
    end
  end

  it "borrows nilable String arguments" do
    ["ri", "iyi"].each do |extension|
      tape_compile(<<-'CODE', extension)
        def width(text : String?) : Int32
          text ? text.size : 0
        end
        def choose(text : String?, n : Int64) : String?
          text
        end
        def optional(text : String, present : Bool) : String?
          present ? text : nil
        end
        present = optional("abc", true)
        absent = optional("abc", false)
        width(present)
        width(absent)
        width(text: present)
        width(text: absent)
        width("abc")
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
        def width(text : String) : Int32
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
        view : String = optional(nil)
        CODE
    end
  end

end

describe "ris String parameter retention" do
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

describe "ris recursive store summaries" do
  it "keeps flat node field types through mutual recursion" do
    tape_compile(<<-'CODE')
      @[OnTape]
      struct N
        getter a : Int32
        def initialize(@a : Int32 = -1)
        end
      end

      @[OnTape]
      struct P
        def initialize
          @nodes = Array(N).new(8)
        end

        def node(a : Int32) : Int32
          @nodes << N.new(a)
          @nodes.size - 1
        end

        def pipe(d : Int32) : Int32
          return 0 if d > 3
          b = other(d + 1)
          node(b)
        end

        def other(d : Int32) : Int32
          pipe(d)
        end
      end
      p = P.new
      puts p.pipe(0)
      CODE
  end

  it "keeps a literal text store through mutual recursion" do
    tape_compile(<<-'CODE')
      class P
        def initialize
          @nodes = Array(String).new(8)
        end

        def node(a : String) : Int32
          @nodes << a
          @nodes.size - 1
        end

        def pipe(d : Int32) : Int32
          return 0 if d > 3
          b = other(d + 1)
          node("x")
        end

        def other(d : Int32) : Int32
          pipe(d)
        end
      end
      p = P.new
      puts p.pipe(0)
      CODE
  end

  it "gives a default in a cycle the roots of its expression" do
    tape_compile(<<-'CODE')
      struct Cell
        def initialize(@n : Int32 = 0)
        end
      end

      @[OnTape]
      struct N
        def initialize(@kind : String, @a : Int32, @text : String,
                       @value : Cell, @args : SlicePool::Run(Int32))
        end
      end

      @[OnTape]
      class P
        def initialize
          @nodes = Array(N).new(8)
          @arguments = SlicePool(Int32).new(8)
        end

        def node(kind : String, a : Int32 = -1, text : String = "",
                 value : Cell = Cell.new,
                 args : SlicePool::Run(Int32) = @arguments.alloc_slice(0),
                 id : Int32 = -1) : Int32
          @nodes << N.new(kind, a, text, value, args)
          @nodes.size - 1
        end

        def pipe(d : Int32, far : P) : Int32
          return 0 if d > 3
          b = other(d + 1, far)
          return far.node("Far", b) if d > 2
          return node("Id", b, id: d) if d > 1
          node("As", b)
        end

        def other(d : Int32, far : P) : Int32
          pipe(d, far)
        end
      end
      p = P.new
      q = P.new
      puts p.pipe(0, q)
      CODE
  end

  it "refuses a class default stored in a cycle" do
    expect_raises(Iyi::TypeException, /cannot store data made in this def/) do
      tape_compile(<<-'CODE')
        class C
        end

        @[OnTape]
        struct P
          def initialize
            @nodes = Array(C).new(8)
          end

          def node(a : Int32 = -1, v : C = C.new) : Int32
            @nodes << v
            @nodes.size - 1
          end

          def pipe(d : Int32) : Int32
            return 0 if d > 3
            b = other(d + 1)
            node(b)
          end

          def other(d : Int32) : Int32
            pipe(d)
          end
        end
        p = P.new
        puts p.pipe(0)
        CODE
    end
  end
end

# How many of the `next`s in the round of the loop counting *counter* have
# a scope reset right before them, and how many there are in all.
private class RoundExits < Iyi::Visitor
  getter nexts = 0
  getter resets = 0

  def initialize(@counter : String)
  end

  def visit(node : Iyi::While)
    cond = node.cond
    names = [] of String
    cond.accept(NameFinder.new(names))
    return true unless names.includes?(@counter)
    count node.body
    false
  end

  def visit(node : Iyi::ASTNode)
    true
  end

  private def count(node : Iyi::ASTNode)
    case node
    when Iyi::While, Iyi::Block, Iyi::Def
      return
    when Iyi::Next
      @nexts += 1
    when Iyi::Expressions
      node.expressions.each_with_index do |exp, i|
        if exp.is_a?(Iyi::Next) && i > 0 &&
           (reset = node.expressions[i - 1]).is_a?(Iyi::Call) &&
           reset.name == "__iyi_scope_reset"
          @resets += 1
        end
      end
    end
    node.accept_children(Children.new(self))
  end

  protected def count_child(node : Iyi::ASTNode)
    count node
  end

  private class Children < Iyi::Visitor
    def initialize(@owner : RoundExits)
    end

    def visit(node : Iyi::ASTNode)
      @owner.count_child node
      false
    end
  end

  private class NameFinder < Iyi::Visitor
    def initialize(@names : Array(String))
    end

    def visit(node : Iyi::Var)
      @names << node.name
      true
    end

    def visit(node : Iyi::ASTNode)
      true
    end
  end
end

private def round_exits(code : String, counter : String) : {Int32, Int32}
  result = tape_compile(code)
  visitor = RoundExits.new(counter)
  result.node.accept visitor
  {visitor.nexts, visitor.resets}
end

describe "ris round exits" do
  # TapeScopeChecker#clean_exits: the round allocates, so its mark stays;
  # nothing before this `next` can have put data on the tape, so its reset
  # is dropped.
  it "drops the reset of a `next` that follows no allocation" do
    exits = round_exits(<<-'CODE', "clean")
      clean = 0
      total = 0
      while clean < 10
        clean += 1
        next if clean.odd?
        text = "n#{clean}"
        total += text.size
      end
      puts total
      CODE
    exits.should eq({1, 0})
  end

  it "keeps the reset of a `next` after an allocation" do
    exits = round_exits(<<-'CODE', "dirty")
      dirty = 0
      total = 0
      while dirty < 10
        dirty += 1
        text = "n#{dirty}"
        total += text.size
        next if dirty.odd?
        total += 1
      end
      puts total
      CODE
    exits.should eq({1, 1})
  end

  # Only sequences, branches and assignments to a local are followed: an
  # exit inside a call's argument keeps its reset.
  it "keeps the reset of a `next` nested in another node" do
    exits = round_exits(<<-'CODE', "nested")
      nested = 0
      total = 0
      while nested < 10
        nested += 1
        total += (nested.odd? ? next : 1) + 0
        text = "n#{nested}"
        total += text.size
      end
      puts total
      CODE
    exits.should eq({1, 1})
  end
end
