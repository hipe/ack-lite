require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"


module Hipe::Parsie
  describe "regexp" do
    extend SpecExtension
    def short_grammar
      name = 'short grammar'
      Grammar.all.has?(name) ? Grammar.all[name] :
        Grammar.new('short grammar') do |g|
          g.add "a thru z", /^[a-z]+$/
          g.test_context = self
        end
    end

    it "should fail on the empty input (1)" do
      short_grammar.must_fail "",  "expecting a thru z and had no input"
    end

    it "should fail on one wrong string (2)" do
      short_grammar.must_fail "123", "expecting a thru z near \"123\""
    end

    it "should parse on one right string (3)" do
      parse = short_grammar.parse! "foo"
      parse.kind_of?(RegexpParse).must_equal true
      parse.tree.must(:regexp, "a thru z") do |v|
        v.must_equal "foo"
      end
    end

    it "should fail when there's still more input (4)" do
      short_grammar.must_fail(
        "foo\nbar",
        "expecting no more input near \"bar\""
      )
    end
  end
end
