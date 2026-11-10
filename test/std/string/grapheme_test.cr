require "./test_helper"

describe String::Grapheme do
  it ".new" do
    String::Grapheme.new("foo", 0...1, 'f').@cluster.should eq 'f'
    String::Grapheme.new("foo", 0...2, 'o').@cluster.should eq "fo"
    String::Grapheme.new("foo", 1...3, 'o').@cluster.should eq "oo"
  end

  it "#to_s" do
    String::Grapheme.new("foo").to_s.should eq "foo"
    String::Grapheme.new('f').to_s.should eq "f"

    String.build do |io|
      String::Grapheme.new("foo").to_s(io)
    end.should eq "foo"
    String.build do |io|
      String::Grapheme.new('f').to_s(io)
    end.should eq "f"
  end

  it "#inspect" do
    String::Grapheme.new("foo").inspect.should eq %(String::Grapheme("foo"))
    String::Grapheme.new('f').inspect.should eq %(String::Grapheme('f'))
  end

  it "#size" do
    String::Grapheme.new("foo").size.should eq 3
    String::Grapheme.new("🙂🙂").size.should eq 2
    String::Grapheme.new('f').size.should eq 1
    String::Grapheme.new('🙂').size.should eq 1
  end

  it "#bytesize" do
    String::Grapheme.new("foo").bytesize.should eq 3
    String::Grapheme.new("🙂🙂").bytesize.should eq 8
    String::Grapheme.new('f').bytesize.should eq 1
    String::Grapheme.new('🙂').bytesize.should eq 4
  end

  it "#==" do
    String::Grapheme.new('f').should eq String::Grapheme.new('f')
    String::Grapheme.new('f').should_not eq String::Grapheme.new("f")
    String::Grapheme.new("foo").should eq String::Grapheme.new("foo")
  end

  it ".break?" do
    String::Grapheme.break?('a', 'b').should be_true

    String::Grapheme.break?('\r', '\n').should be_false
    String::Grapheme.break?('\r', 'a').should be_true
    String::Grapheme.break?('a', '\n').should be_true

    String::Grapheme.break?('o', '\u0308').should be_false
  end
end

describe String do
  it "#grapheme_size" do
    "foo".grapheme_size.should eq 3
    "🙂🙂".grapheme_size.should eq 2
    "f".grapheme_size.should eq 1
    "🙂".grapheme_size.should eq 1
  end

  it "#graphemes" do
    "abc".graphemes.map(&.to_s).should eq ["a", "b", "c"]
    "möp".graphemes.map(&.to_s).should eq ["m", "ö", "p"]
    "möp".graphemes.map(&.to_s).should eq ["m", "o\u0308", "p"]
    "뢴".graphemes.map(&.to_s).should eq ["\u1105\u116c\u11ab"]
    "\r\n".graphemes.map(&.to_s).should eq ["\r\n"]
  end

  # These are just a couple of manual tests, the lot of automated specs is in grapheme_break_test.cr
  describe "#each_grapheme" do
    it_iterates_graphemes "", [] of String
    it_iterates_graphemes "\x00", [Char::ZERO]
    it_iterates_graphemes "x", ['x']
    it_iterates_graphemes "basic", ['b', 'a', 's', 'i', 'c']
    it_iterates_graphemes "möp", ['m', "o\u0308", 'p']
    it_iterates_graphemes "\r\n", ["\r\n"]
    it_iterates_graphemes "\n\n", ['\n', '\n']
    it_iterates_graphemes "\t*", ['\t', '*']
    it_iterates_graphemes "뢴", ["\u1105\u116C\u11AB"]
    it_iterates_graphemes "ܐ܏ܒܓܕ", ['\u0710', "\u070F\u0712", '\u0713', '\u0715']
    it_iterates_graphemes "ำ", ['\u0E33']
    it_iterates_graphemes "ำำ", ["\u0E33\u0E33"]
    it_iterates_graphemes "สระอำ", ['\u0E2A', '\u0E23', '\u0E30', "\u0E2D\u0E33"]
    it_iterates_graphemes "*뢴*", ['*', "\u1105\u116C\u11AB", '*']
    it_iterates_graphemes "*👩‍❤️‍💋‍👩*", ['*', "\u{1F469}\u200D\u2764\uFE0F\u200D\u{1F48B}\u200D\u{1F469}", '*']
    it_iterates_graphemes "👩‍❤️‍💋‍👩", ["\u{1F469}\u200D\u2764\uFE0F\u200D\u{1F48B}\u200D\u{1F469}"]
    it_iterates_graphemes "🏋🏽‍♀️", ["\u{1F3CB}\u{1F3FD}\u200D\u2640\uFE0F"]
    it_iterates_graphemes "🙂", ['\u{1F642}']
    it_iterates_graphemes "🙂🙂", ['\u{1F642}', '\u{1F642}']
    it_iterates_graphemes "🇩🇪", ["\u{1F1E9}\u{1F1EA}"]
    it_iterates_graphemes "🏳️‍🌈", ["\u{1F3F3}\uFE0F\u200D\u{1F308}"]
  end
end
