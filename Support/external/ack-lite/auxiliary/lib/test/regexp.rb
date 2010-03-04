require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"


module Hipe::Parsie
  describe "single regex grammar" do
    extend SpecExtension
    before do
      Grammar.clear_tables!
      @g = Grammar.new('short grammar') do |g|
        g.add "a thru z", /^[a-z]+$/
        g.test_context = self
      end
    end

    it "should fail on the empty input (1)" do
      @g.must_fail "",  "expecting a thru z and had no input"
    end

    it "should fail on one wrong string (2)" do
      @g.must_fail "123", "expecting a thru z at end of input near \"123\""
    end

    it "should parse on one right string (3)" do
      parse = @g.parse! "foo"
      parse.kind_of?(RegexpParse).must_equal true
      parse.tree.must(:regexp, "a thru z") do |v|
        v.must_equal "foo"
      end
    end

    it "should fail when there's still more input (4)" do
      @g.must_fail "foo\nbar", "expecting no more input near \"foo\""
    end
  end
end
