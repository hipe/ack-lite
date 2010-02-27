require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"


module Hipe::Parsie
  describe "tokenizer" do
    extend Hipe::Skippy
    it "should" do
      t = StringLinesTokenizer.new("")
      t.describe.must_match "at beginning of input"
      t.pop.must_equal nil
      t.pop.must_equal nil
      t.describe.must_match "at end of input"
    end
    it "should also" do
      t = StringLinesTokenizer.new("foo")
      t.pop.must_equal "foo"
      t.describe.must_match 'near "foo"'
      t.pop.must_equal nil
      t.describe.must_match 'at end of input near "foo"'
    end
    it "should also this" do
      t = StringLinesTokenizer.new("foo\nbar")
      t.pop.must_equal "foo"
      t.pop.must_equal "bar"
      t.describe.must_match 'near "bar"'
      t.pop.must_equal nil
      t.describe.must_match 'at end of input near "bar"'
    end
  end
end
