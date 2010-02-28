require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"


module Hipe::Parsie
  describe "union basic" do
    extend Hipe::Skippy
    before do
      Grammar.clear_tables!
      @g = Grammar.new('short grammar') do |g|
        g.add "string or regexp", 'abc123'
        g.add "string or regexp", /^[a-z]+[0-9]+$/
      end
    end

    it "should fail on the empty input" do
      tree = @g.parse!("")
      tree.must_equal nil
      pf = @g.parse_fail
      pf.kind_of?(ParseFail).must_equal true
      desc = pf.describe
      desc.must_equal(
        "expecting \"abc123\" or string or regexp and had no input")
    end

    it "should fail on bad string" do
      tree = @g.parse!("123abc")
      tree.must_equal nil
      pf = @g.parse_fail
      pf.kind_of?(ParseFail).must_equal true
      desc = pf.describe
      desc.must_equal(
        "expecting \"abc123\" or string or regexp near \"123abc\""
      )
    end

    it "should parse on one good string using string symbol" do
      parse = @g.parse!("abc123")
      parse.tree.value.value.must_equal "abc123"
      parse.tree.value.type.must_equal :string

    end

    skipit "should parse on one good string using regex symbol" do
      parse = @g.parse!("def789")
      parse.tree.value.value.must_equal "def789"
      parse.tree.value.type.must_equal :regexp
    end
  end
end
