require 'minitest/autorun'  # unit and spec
require 'ruby-debug'

class SingleStringGrammarSpec < MiniTest::Spec
  TestRoot = File.expand_path('..',File.dirname(__FILE__))
  def self.skipit msg, &b; puts "skipping: #{msg}" end
end

require File.join(SingleStringGrammarSpec::TestRoot,'parsie')

module Hipe::Parsie
  describe "single string grammar" do
    before do
      Grammar.clearTables
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
      desc.must_match(/\Aexpecting "foo" at end of input\Z/)
    end
    it "should fail on one wrong string" do
      tree = @g.parse!("bar")
      tree.must_equal nil
      pf = @g.parse_fail
      pf.kind_of?(ParseFail).must_equal true
      desc = pf.describe
      desc.must_match  "expecting \"foo\" at end of input after \"bar\""
      puts pf.describe
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
