require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"


module Hipe::Parsie
  describe "grammar5 - digits" do
    extend Hipe::Skippy
    def page5
      Grammar.clear_tables!
      @page5 = Grammar.new('minimalesque grammar') do |g|
        g.add :list, [:list, :digits]
        g.add :list, :digits
        g.add :digits, /\A[0-9]+\Z/
        g.reference_check
      end
      @page5
    end

    def win_tree(parser,input)
      parse = parser.parse!(input)
      tree = parse.tree
      tree
    end

    skipit "should parse on one valid token" do
      tree = win_tree(page5, "123")
      tree.value.value.must_equal "123"
    end

    skipit(
      "should parse on one valid token but fail on second invalid token"
    ) do
      parser = page5
      resp = parser.parse! "123\nabc"
      resp.must_equal nil
      parser.parse_fail.describe.must_equal(
        "expecting no more input near \"123\""
      )
    end

    it "should parse two valid tokens" do
      parser = page5
      resp = parser.parse! "123\n456"
      debugger
      'x'
    end
  end
end
