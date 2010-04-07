# shared setup
require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
addme = File.expand_path('../../lib',__FILE__)
$:.unshift(addme) unless $:.include?(addme)
require 'man-parse'
class String
  def cleanup num
    re = Regexp.new("^#{' '*num}")
    gsub!(re,'')
    self
  end
end

module Hipe
  module ManParse
    describe self do
      it "(test1) should complaing that it is expecting option line" do
        Parsie::Debug.verbose = false
        foo = <<-HERE.cleanup(8)
        slkejfa
        lsejf
        HERE
        gram = Commands.grammar[:grammar1]
        rslt = gram.parse!(foo)
        rslt.fail.must_match(
          %r{expecting not_option_line or options_header at end of input}
        )
      end

      it "(test2) should match the options line" do
        Parsie::Debug.verbose = false
        foo = <<-HERE.cleanup(8)
        abcdef
        ghijk
        OPTIONS
        HERE
        gram = Commands.grammar[:grammar1]
        rslt = gram.parse!(foo)
        rslt.fail.message.must_match(
         %r{expecting switch at end of input near \"OPTIONS\"})
      end

      it "(test3) should match one option like this" do

      end
    end
  end
end
