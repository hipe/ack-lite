require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"


module Hipe::Parsie
  describe "grammar5 - digit" do
    extend Hipe::MinitestExtraClassMethods
    include Hipe::MinitestExtraInstanceMethods
    def page5
      Grammar.clear_tables!
      @page5 = Grammar.new('minimalesque grammar') do |g|
        g.add :list, [:list, :digit]
        g.add :list, :digit
        g.add :digit, /\A[0-9]+\Z/
        g.reference_check
      end
      @page5
    end

    def win_tree(parser,input)
      parse = parser.parse!(input)
      tree = parse.tree
      tree
    end

    it "should parse on one valid token" do
      tree = win_tree(page5, "123")
      tree.value.value.must_equal "123"
    end

    it(
      "should parse on one valid token but fail on second invalid token"
    ) do
      parser = page5
      resp = parser.parse! "123\nabc"
      resp.must_equal nil
      parser.parse_fail.describe.must_equal(
        "expecting digit near \"abc\""
      )
    end

    # receiver out here is Grammar5DigitSpec Class object

    # @todo need structure assert
    it "should parse two valid tokens" do
      parser = page5
      parse = parser.parse! "123\n456"
      tree = parse.tree
      with tree do |it|
        it.type.must_equal        :union
        it.symbol_name.must_equal :list
        with it.value do |it|
          it.type.must_equal        :concat
          it.symbol_name.must_equal :list
          with it.value do |it|
            assert_kind_of Array, it
            it.size.must_equal 2
            it1, it2 = it
            with it1 do |it|
              it.type.must_equal :union
              it.symbol_name.must_equal :list
              with it.value do |it|
                it.type.must_equal :regexp
                it.symbol_name.must_equal :digit
                it.value.must_equal "123"
              end
            end
            with it2 do |it|
              it.type.must_equal :regexp
              it.symbol_name.must_equal :digit
              it.value.must_equal "456"
            end
          end
        end
      end
    end
  end
end
