require File.dirname(__FILE__)+'/support/common-setup.rb'

module Hipe::Parsie
  describe "regexp pushback and range" do
    extend SpecExtension

    def repeater_grammar
      name = 'repeater grammar'
      Grammar.all.has?(name) ? Grammar.all[name] :
        Grammar.new(name) do |g|
          g.add :digits, [(1..-1), :digit]
          g.add :digit, /^[0-9]+$/
          g.test_context = self
        end
    end

    it "bad (101)" do
      repeater_grammar.parse!("abc\ndef\nghi").must_fail(
        "expecting digit near \"abc\""
      )
    end

    def assert_range_parse(type, name, arr, parse)
      parse.fail.must_equal nil
      tree = parse.tree
      assert_range_parse_tree(type, name, arr, tree)
    end

    def assert_range_parse_tree(type, name, arr, tree)
      assert_instance_of(ParseTree, tree)
      assert_equal(:range, tree.type)
      assert_kind_of(Array,tree.value)
      assert_equal(arr.size,tree.value.size)
      arr.each_with_index do |v, idx|
        tree.value[idx].must(type, name){|v| v.must_equal v}
      end
    end

    it "good (102-1)" do
      parse = repeater_grammar.parse!("123")
      assert_range_parse(:regexp, :digit, ['123'], parse)
    end

    it "good good (102-2)" do
      parse = repeater_grammar.parse!("123\n456")
      assert_range_parse(:regexp, :digit, %w(123 456), parse)
    end

    it "good bad (103)" do
      parse = repeater_grammar.parse!("123\nabc").must_fail(
        "expecting digit near \"abc\""
      )
    end

    it "good good good (104)" do
      parse = repeater_grammar.parse!("123\n456\n789")
      assert_range_parse(:regexp, :digit, %w(123 456 789), parse)
    end

    def repeater_grammar_no_cap
      name = 'repeater grammar no cap'
      Grammar.all.has?(name) ? Grammar.all[name] :
        Grammar.new(name) do |g|
          g.add :digits, [(1..-1), :digit], :capture => false
          g.add :digit, /^[0-9]+$/
          g.test_context = self
        end
    end

    # non-capturing symbols of repeating ranges still
    # indicate how many times they matched
    #
    def assert_no_capture(num, parse)
      parse.fail.must_equal nil
      parse.tree.value.must_equal :no_capture
      parse.num_satisfied.must_equal num
    end

    it "no capture should parse three (201)" do
      repeater_grammar_no_cap.kind_of?(Grammar).must_equal true
      parse = repeater_grammar_no_cap.parse!("123\n456\n789")
      assert_no_capture(3, parse)
    end

    it "no capture should parse one (202)" do
      repeater_grammar_no_cap.kind_of?(Grammar).must_equal true
      parse = repeater_grammar_no_cap.parse!("123")
      assert_no_capture(1, parse)
    end

    def proto_sentence_g
      name = 'proto sentence g'
      Grammar.all.has?(name) ? Grammar.all[name] :
        Grammar.new(name) do |g|
          g.add :sentence, ['a', [(0..-1),:b]]
          g.add :b, 'b'
          g.test_context = self
        end
    end

    it "just a (250)" do
      parse = proto_sentence_g.parse!("a")
      parse.tree
      parse.unparse.must_equal ['a']
    end

    it "a b a (251)" do
      parse = proto_sentence_g.parse!("a\nb\na").must_fail(
        "expecting \"b\" near \"a\""
      )
    end

    it "a b (252)" do
      parse = proto_sentence_g.parse!("a\nb")
      parse.tree.must(:concat, :sentence) do |arr|
        arr[0].must(:string,nil){|v| v.must_equal 'a'}
        assert_range_parse_tree(:string, :b, %w(b), arr[1])
      end
      parse.unparse.must_equal ['a','b']
    end

    it "a b b (253)" do
      parse = proto_sentence_g.parse!("a\nb\nb")
      parse.tree.must(:concat, :sentence) do |arr|
        arr[0].must(:string,nil){|v| v.must_equal 'a'}
        assert_range_parse_tree(:string, :b, %w(b b), arr[1])
      end
      parse.unparse.must_equal ['a','b','b']
    end

    it "a b b c (254)" do
      parse = proto_sentence_g.parse!("a\nb\nb\nc").must_fail(
        "expecting \"b\" near \"c\""
      )
    end

    def sentence_grammar
      name = 'sentence grammar'
      Grammar.all.has?(name) ? Grammar.all[name] :
        Grammar.new(name) do |g|
          g.add :sentence,[:word,[(0..-1),[:word_separator, :word]],:punct]
          g.add :word_separator, /^( |-)/
          g.add :punct, /^(\.|\?|!)+/
          g.add :word, /^([a-zA-Z0-9]+)/
          g.test_context = self
        end
    end

    it "whats happening here (301)" do
      input_text = <<-HERE.test_strip(8)
        Dick and Jane climbed a tree.
      HERE
      parse = sentence_grammar.parse!(input_text)
      parse.unparse.must_equal(
        ["Dick", " ", "and", " ", "Jane", " ",
          "climbed", " ", "a", " ", "tree", "."]
      )
    end

    def the_grammar
      name = 'the grammar'
      Grammar.all.has?(name) ? Grammar.all[name] :
        Grammar.new(name) do |g|
          g.add :document, :paragraphs
          g.add :paragraphs, [ :paragraph,  :more_paragraphs ]
          g.add :more_paragraphs, [(0..-1),[:paragraph_separator, :paragraph]]
          g.add :paragraph, :sentences
          g.add :paragraph_separator, ""
          g.add :sentences, [(1..-1), :sentence]
          g.add :sentence, [:word, [(0..-1),:extra_word], :punct]
          g.add :extra_word, [[(0..1), :word_separator], :word]
          g.add :word_separator, /^( |-)/
          g.add :punct, /^(?:\.|\?|!)+ */
          g.add :word, /^[a-zA-Z0-9';]+/
          g.test_context = self
        end
    end

    it "should build the grammar (501)" do
      assert_kind_of Grammar, the_grammar
    end

    it "should parse two minimal paragraphs (503)" do
      input_text = "boo coo.\n\ndoo foo."
      parse = the_grammar.parse!(input_text)
      parse.unparse.must_equal(
        ["boo", " ", "coo", ".", "", "doo", " ", "foo", "."]
      )
      parse.ok?.must_equal true
      parse.done?.must_equal false
    end

    it "should parse two minimallest paragraphs (504)" do
      input_text = "boo.\n\ncoo."
      parse = the_grammar.parse!(input_text)
      parse.fail.must_equal nil
    end

    it "should parse three minimallest paragraphs (505)" do
      input_text = "boo.\n\ncoo.\n\nfoo."
      parse = the_grammar.parse!(input_text)
      parse.fail.must_equal nil
      parse.ok?.must_equal true
      parse.done?.must_equal false
      parse.unparse.must_equal ["boo", ".", "", "coo", ".", "", "foo", "."]
    end

    # i've had 18 straight whiskeys.  i think that's the record

    it "(507)" do
      input_text = <<-HERE.test_strip(8)
        foo bar.
      HERE
      parse = the_grammar.parse!(input_text)
      parse.ok?.must_equal true
      parse.unparse.must_equal ["foo", " ", "bar", "."]
    end

    it "(508)" do
      input_text = <<-HERE.test_strip(8)
        foo
        bar.
      HERE
      parse = the_grammar.parse!(input_text)
      parse.ok?.must_equal true
      parse.unparse.must_equal ["foo", "bar", "."]
    end


    it "should parse two minimal paragraphs (510)" do
      input_text = <<-HERE.test_strip(8)
        Dick and Jane climbed a tree.  They decided to get married.

        They didn't get married for love; they got married for tax purposes.

        Is this the nature of the universe?  Maybe.  But it is certainly the
        nature of them.
      HERE
      parse = the_grammar.parse!(input_text)
      parse.ok?.must_equal true
      parse.done?.must_equal false
      tgt =
      ["Dick", " ", "and", " ", "Jane", " ", "climbed", " ", "a", " ", "tree",
       ".  ", "They", " ", "decided", " ", "to", " ", "get", " ", "married",
       ".", "", "They", " ", "didn't", " ", "get", " ", "married", " ",
       "for", " ", "love;", " ", "they", " ", "got", " ", "married", " ",
       "for", " ", "tax", " ", "purposes", ".", "", "Is", " ", "this", " ",
       "the", " ", "nature", " ", "of", " ", "the", " ", "universe", "?  ",
       "Maybe", ".  ", "But", " ", "it", " ", "is", " ", "certainly", " ",
      "the", "nature", " ", "of", " ", "them", "."]
      assert_array(tgt, parse.unparse)
    end
  end
end

