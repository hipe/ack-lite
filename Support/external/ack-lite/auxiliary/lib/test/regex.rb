require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"


module Hipe::Parsie
  describe "single regex grammar" do
    extend Hipe::Skippy
    before do
      Grammar.clear_tables!
      @g = Grammar.new('short grammar') do |g|
        g.add "a thru z", /^[a-z]+$/
      end
    end

    it "should fail on the empty input" do
      tree = @g.parse!("")
      tree.must_equal nil
      pf = @g.parse_fail
      pf.kind_of?(ParseFail).must_equal true
      desc = pf.describe
      desc.must_match "expecting a thru z and had no input"
    end

    it "should fail on one wrong string" do
      tree = @g.parse!("123")
      tree.must_equal nil
      pf = @g.parse_fail
      pf.kind_of?(ParseFail).must_equal true
      desc = pf.describe
      desc.must_match "expecting a thru z at end of input near \"123\""
    end

    it "should parse on one right string" do
      tree = @g.parse!("foo")
      tree.kind_of?(RegexpParse).must_equal true
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
