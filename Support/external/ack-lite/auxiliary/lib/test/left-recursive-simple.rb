require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"


module Hipe::Parsie
  class ParseTree
    include MiniTest::Assertions
    def must need_type, need_name, size = nil
      type.must_equal need_type
      symbol_name.must_equal need_name
      unless size.nil?
        val = value
        assert_kind_of Array, val
        val.size.must_equal size
      end
      yield value if block_given?
    end
  end

  describe "left recursive simple" do
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

    it "should parse on one valid token (1)" do
      tree = win_tree(page5, "123")
      tree.must :union, :list do |tree|
        tree.must :regexp, :digit do |val|
          val.must_equal "123"
        end
      end
    end

    it(
      "should parse on one valid token but fail on second invalid token (2)"
    ) do
      parser = page5
      resp = parser.parse! "123\nabc"
      resp.must_equal nil
      parser.parse_fail.describe.must_equal(
        "expecting digit at end of input near \"abc\""
      )
    end

    # receiver out here is Grammar5DigitSpec Class object

    it "should parse two valid tokens (3)" do
      parser = page5
      parse = parser.parse! "123\n456"
      tree = parse.tree
      tree.must :union, :list do |tree|
        tree.must :concat, :list, 2 do |arr|
          arr[0].must :union, :list do |tree|
            tree.must :regexp, :digit do |v|
              v.must_equal "123"
            end
          end
          arr[1].must :regexp, :digit do |v|
            v.must_equal "456"
          end
        end
      end
    end

    it "should parse three valid tokens (4)" do
      parser = page5
      parse = parser.parse! "111\n112\n113"
      tree = parse.tree
      tree.must :union, :list do |tree|
        tree.must :concat, :list, 2 do |arr1|
          arr1[0].must :union, :list do |tree|
            tree.must :concat, :list do |arr2|
              arr2[0].must :union, :list do |re|
                re.must :regexp, :digit do |val|
                  val.must_equal "111"
                end
              end
              arr2[1].must :regexp, :digit do |val|
                val.must_equal "112"
              end
            end
          end
          arr1[1].must :regexp, :digit do |val|
            val.must_equal "113"
          end
        end
      end
    end
  end
end
