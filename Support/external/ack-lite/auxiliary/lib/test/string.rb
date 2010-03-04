require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"


module Hipe::Parsie
  describe "single string grammar" do
    extend SpecExtension
    before do
      Grammar.clear_tables!
      @g = Grammar.new('short grammar') do |g|
        g.add "the string foo", "foo"
        g.test_context = self
      end
    end

    it "should fail on the empty input (1)" do
      @g.must_fail "", "expecting \"foo\" and had no input"
    end

    it "should fail on one wrong string (2)" do
      @g.must_fail "bar", "expecting \"foo\" at end of input near \"bar\""
    end

    it "should parse on one right string (3)" do
      parse = @g.parse!("foo")
      parse.kind_of?(StringParse).must_equal true
      parse.tree.must(:string, "the string foo")
      parse.tree.value.must_equal "foo"
    end

    it "should fail when there's still more input (4)" do
      @g.must_fail "foo\nbar", "expecting no more input near \"foo\""
    end
  end
end
