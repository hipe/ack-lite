require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"

module Hipe::Parsie
  describe "concat basic" do
    extend SpecExtension
    def grammar_empty
      Grammar.clear_tables!
      Grammar.new('flat grammar of zero terminals') do |g|
        g.add :empty_list, []
        g.test_context = self
      end
    end

    it "should build a flat grammar with terminals (1)" do
      g1 = grammar_empty
      assert_kind_of(Grammar, g1)
      sym = g1.symbol(:empty_list)
      assert_kind_of ConcatProduction, sym
    end

    it "empty grammar should know about its offsets (2)" do
      parse = grammar_empty.build_start_parse
      parse.satisfied_offset.must_equal(-1)
      parse.final_offset.must_equal(-1)
    end

    def grammar_one_nonzero_string
      Grammar.new('grammar with one nonzero string') do |g|
        g.add :one_nonzero_string, ['foo']
        g.test_context = self
      end
    end

    it(
    "single token nonzero string grammar should know about its offsets (3)"
    ) do
      g = grammar_one_nonzero_string.satisfied_and_final_offset_must_be(0,0)
    end

    def grammar_a_nonzero_regexp
      Grammar.new('grammar with one nonzero regexp') do |g|
        g.add :utterance, [:some_nonzero_regex_symbol]
        g.add :some_nonzero_regex_symbol, /a/
        g.test_context = self
      end
    end

    it("single token nonzero regexp grammar should know its offsets (4)") do
      grammar_a_nonzero_regexp.satisfied_and_final_offset_must_be(0,0)
    end

    def grammar_a_zero_regexp
      Grammar.new('grammar with one zero regexp') do |g|
        g.add :a_zero_regexp, [:some_zero_regex_symbol]
        g.add :some_zero_regex_symbol, /^(?:foobar)?[abcdefg]*$/
        g.test_context = self
      end
    end

    it("single token zero regexp grammar should know its offsets (5)") do
      grammar_a_zero_regexp.satisfied_and_final_offset_must_be(-1,0)
    end

    def grammar_zero_one
      Grammar.new('grammar zero one') do |g|
        g.add :utterance, [:some_zero_regex_symbol, 'width one']
        g.add :some_zero_regex_symbol, /^(?:foobar)?[abcdefg]*$/
        g.test_context = self
      end
    end

    it("zero one should know its offsets (6)") do
      grammar_zero_one.satisfied_and_final_offset_must_be(1,1)
    end

    def grammar_one_zero
      Grammar.new('grammar one zero') do |g|
        g.add :utterance, ['width one',:some_zero_regex_symbol]
        g.add :some_zero_regex_symbol, /^(?:foobar)?[abcdefg]*$/
        g.test_context = self
      end
    end

    it("one zero should know its offsets (7)") do
      grammar_one_zero.satisfied_and_final_offset_must_be(0,1)
    end

    def grammar_one_zero_zero
      Grammar.new('grammar one zero zero') do |g|
        g.add :utterance, ['width one',:some_zero_regex_symbol, :r2]
        g.add :some_zero_regex_symbol, /^(?:foobar)?[abcdefg]*$/
        g.add :r2, /^a*$/
        g.test_context = self
      end
    end

    it("one zero zero should know its offsets (8)") do
      grammar_one_zero_zero.satisfied_and_final_offset_must_be(0,2)
    end

    ### parses

    def grammar_a_zero_string
      Grammar.clear_tables!
      Grammar.new('grammar with one zero string') do |g|
        g.add :a_zero_string, ['']
        g.test_context = self
      end
    end

    it("single token zero string grammar should know about its offsets (9)")do
      grammar_a_zero_string.satisfied_and_final_offset_must_be(-1,0)
    end

    it (
      "what happens with the zero string grammar on the zero string? (10)"
    ) do
      # the tokenizer makes zero tokens out of the empty string so none
      # are ever passed to the parser
      g1 = grammar_a_zero_string
      parse = g1.parse!("")
      parse.ok?.must_equal true
      parse.done?.must_equal false
      parse.tree.must(:concat, :a_zero_string){|v| v.must_equal [nil] }
    end
  end
end
