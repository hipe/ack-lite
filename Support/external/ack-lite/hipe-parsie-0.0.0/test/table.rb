require File.dirname(__FILE__)+'/support/common-setup.rb'

module Hipe::Parsie
  describe "grammar tables" do
    extend SpecExtension
    it "should raise on unresolved references, singular (table-1)" do
      e = proc do
        Grammar.clear_tables!
        g = Grammar.new("thingo") do |g|
          g.add :blah, [:there, 'hi', :not_there, 'hello']
          g.add :there, 'foo'
          g.reference_check
        end
      end.must_raise(ParseParseFail)
      tgt = <<-HERE.unmarginalize!
        The symbol referred to in the "thingo" grammar was missing: :not_there
      HERE
      assert_string tgt, e.message, 'error message'
    end

    it "should raise on unresolved references, plural (table-2)" do
      e = proc do
        Grammar.clear_tables!
        g = Grammar.new("thingo") do |g|
          g.add :blah, [:not_there, 'hi', :not_there_either, 'hello']
          g.reference_check
        end
      end.must_raise(ParseParseFail)
      target = <<-HERE.unmarginalize!.one_line!
        The following symbols referred to in the "thingo" grammar were
        missing: (:not_there, :not_there_either)
      HERE
      assert_string target, e.message, 'error message'
    end

    it "should not raise on unresolved references "+
      "if not asked to (table-3)" do
      assert_block do
        Grammar.clear_tables!
        g = Grammar.new("thingo") do |g|
          g.add :blah, [:not_there, 'hi', :not_there_either, 'hello' ]
        end
        true
      end
    end

    def minimal_g
      @@minimal_grammar ||= Grammar.new('foobric'){}
    end

    it "must make a really cool whiney noise when trying to parse bad (4)" do

      except = assert_raises Hipe::Parsie::ParseFail do
        minimal_g.parse!(1)
      end
      str = except.message
      tgt = <<-HERE.unmarginalize!.one_line!
        Fixnum couldn't be used as a StringLinesTokenizer because it doesn't
        respond to split, it couldn't be used as a StackeyStream because it
        doesn't respond to closed? or gets and it couldn't be used as a
        AbstractTokenizer because it doesn't respond to
        never_had_tokens?, has_no_more_tokens?, get_context_near_end,
        get_context_near, peek, pop! or push
      HERE
      assert_string tgt, str, "this is a fragile test"
    end

    it "should induce tokenizer from string (table-5)" do
      tox = minimal_g.induce_tokenizer('foo')
      assert_kind_of(StringLinesTokenizer,tox,'should make tokenizer')
    end

    it "should induce tokenizer from IO-like (table-6)" do
      tox = minimal_g.induce_tokenizer(StringIO.new)
      assert_kind_of(StackeyStream, tox, 'need stackey stream')
    end

    module StubTokenizer
      class << self
        %w(offset never_had_tokens?  has_no_more_tokens? get_context_near_end
        get_context_near peek pop! push).each{|x| define_method(x){} }
      end
    end

    it "should leave tokenizer intact if it is ok (table-7)" do
      tox = minimal_g.induce_tokenizer(StubTokenizer)
      assert_equal(Hipe::Parsie::StubTokenizer, tox, 'leave stub alone')
    end
  end
end
