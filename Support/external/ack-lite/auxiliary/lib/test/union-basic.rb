require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"


module Hipe::Parsie
  describe "union basic" do
    extend SpecExtension
    before do
      Grammar.clear_tables!
      @g = Grammar.new('short grammar') do |g|
        g.add "string or regexp", 'abc123'
        g.add "string or regexp", /^[a-z]+[0-9]+$/
        g.test_context = self
      end
    end

    it "should fail on the empty input (1)" do
      @g.must_fail("",
        "expecting \"abc123\" or string or regexp and had no input")
    end

    it "should fail on bad string (2)" do
      @g.must_fail("123abc",
        ("expecting \"abc123\" or string or regexp at "<<
        "end of input near \"123abc\""))
    end

    it "should parse on one good string using string symbol (3)" do
      parse = @g.parse!("abc123")
      parse.failed?.must_equal false
      assert_kind_of UnionParse, parse
      parse.tree.must :string, "string or regexp" do |v|
        v.must_equal "abc123"
      end
    end

    it "should parse on one good string using regex symbol (4)" do
      parse = @g.parse!("def789")
      parse.failed?.must_equal false
      parse.tree.must :regexp, "string or regexp" do |v|
        v.must_equal "def789"
      end
    end
  end
end
