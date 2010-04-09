require File.dirname(__FILE__)+'/support/common-setup.rb'

module Fake
  LooksLike = Hipe::Parsie::LooksLike
  class StringLinesTokenizer
    LooksLike.enhance(self).looks_like(:string).if_responds_to? :split
  end

  module StackeyStream
    LooksLike.enhance(self) do |it|
      it.looks_like(:stack).when_responds_to %w(closed? gets)
      it.wont_override %w(peek pop push offset)
    end
  end

  module AbstractTokenizer
    LooksLike.enhance(self).looks_like(:tokenizer).when_responds_to %w(
      offset never_had_tokens?  has_no_more_tokens? get_context_near_end
      get_context_near peek pop! push
    )
  end

  describe LooksLike do
    extend Hipe::Parsie::SpecExtension
    it "should blah (ll-1)" do
      StringLinesTokenizer.looks_like_string?(1).must_equal false
      StringLinesTokenizer.looks_like_string?('str').must_equal true
    end

    it "reflects (ll-2)" do
      tgt = [StringLinesTokenizer.looks.describe,
      StackeyStream.looks.describe,
      AbstractTokenizer.looks.describe].join(' ')

      str = <<-HERE.unmarginalize!.one_line!
      to be a StringLinesTokenizer it must define split. to
      be a StackeyStream it must define closed? and gets. StackeyStream
      will not override peek, pop, push and offset. to be a
      AbstractTokenizer it must define offset, never_had_tokens?,
      has_no_more_tokens?, get_context_near_end, get_context_near,
      peek, pop! and push.
      HERE

      assert_string tgt, str, 'descriptions should look good'
    end

    it "should foo (ll-3)" do
      arr = []
      assert_equal(false, StackeyStream.looks.ok?(arr),
        "arr not ok for stackey"
      )
      str = StackeyStream.looks.not_ok_because(arr)
      tgt = <<-HERE.unmarginalize!.one_line!
      it couldn't be used as a StackeyStream because it doesn't respond to
      closed? or gets and it already responds to pop and push
      HERE
      assert_string tgt, str, 'should look right'
    end
  end
end
