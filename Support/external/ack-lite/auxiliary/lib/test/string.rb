require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"


module Hipe::Parsie
  describe "single string grammar" do
    extend Hipe::Skippy
    before do
      Grammar.clear_tables!
      @g = Grammar.new('short grammar') do |g|
        g.add "the string foo", "foo"
      end
    end
    it "should fail on the empty input" do
      tree = @g.parse!("")
      tree.must_equal nil
      pf = @g.parse_fail
      pf.kind_of?(ParseFail).must_equal true
      desc = pf.describe
      desc.must_match(/\Aexpecting "foo" and had no input\Z/)
    end
    it "should fail on one wrong string" do
      tree = @g.parse!("bar")
      tree.must_equal nil
      pf = @g.parse_fail
      pf.kind_of?(ParseFail).must_equal true
      desc = pf.describe
      desc.must_match  "expecting \"foo\" at end of input near \"bar\""
    end
    it "should parse on one right string" do
      tree = @g.parse!("foo")
      tree.kind_of?(StringParse).must_equal true
    end
    it "should fail when there's still more input" do
      tree = @g.parse!("foo\nbar")
      tree.must_equal nil
      fail = @g.parse_fail
      fail.kind_of?(ParseFail).must_equal true
      fail.describe.must_match "expecting end of input near \"foo\""
    end
  end
end
