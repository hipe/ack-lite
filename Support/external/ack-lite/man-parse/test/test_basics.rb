require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
addme = File.expand_path('../../lib',__FILE__)
$:.unshift(addme) unless $:.include?(addme)

require 'man-parse'

module Hipe
  module ManParse
    describe self do
      it "should make request with hash" do
        foo = <<-HERE.gsub(/^    /,'')
        slkejfa
        lsejf
        HERE
        Hipe::Parsie::Debug.true = true
        g = Commands.grammar[:grammar1]
        r = g.parse!(foo)
        debugger; 'x'
      end
    end
  end
end
