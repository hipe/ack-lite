require File.dirname(__FILE__)+'/support/common-setup.rb'

module Hipe::Parsie
  describe "tokenizer" do
    it "should do this (1)" do
      t = StringLinesTokenizer.new("")
      t.describe.must_match "and had no input"
      t.pop!.must_equal nil
      t.pop!.must_equal nil
      t.describe.must_equal "and had no input"
    end
    it "should also do this (2)" do
      t = StringLinesTokenizer.new("foo")
      t.pop!.must_equal "foo"
      t.describe.must_match 'near "foo"'
      t.pop!.must_equal nil
      t.describe.must_equal 'at end of input near "foo"'
    end
    it "should also this too (3)" do
      t = StringLinesTokenizer.new("foo\nbar")
      t.pop!.must_equal "foo"
      t.pop!.must_equal "bar"
      t.describe.must_match 'near "bar"'
      t.pop!.must_equal nil
      t.describe.must_equal 'at end of input near "bar"'
    end
  end
end
