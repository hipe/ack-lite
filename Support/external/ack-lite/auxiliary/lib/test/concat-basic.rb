require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"


module Hipe::Parsie
  describe "simplesque grammar" do
    extend Hipe::Skippy
    def page5
      Grammar.clear_tables!
      @page5 = Grammar.new('minimalesque grammar') do |g|
        g.add :list, [:list, :digit]
        g.add :list, :digit
        g.add :digit, /\A[0-9]+\Z/
      end
      @page5
    end

    it "should build the grammar" do
      assert_kind_of(Grammar, page5)
    end

    it "should do to_bnf" do
      g = Grammar.new('grammar for bnf') do |g|
        g.add :list, [:list, :digit]
        g.add :list, :digit
        g.add :digit, /\A[0-9]+\Z/
      end
      target = <<-'HERE'.test_strip(6)
        list   ::=  list digit.
        list   ::=  digit.
        digit  ::=  /\A[0-9]+\Z/.
      HERE
      str = g.to_bnf
      str.must_equal target
    end

    it "should do insp" do
      g = page5
      sym = g.symbol(:list)
      par = sym.spawn(ParseContext.new)
      target = /.*UnionParse.*ConcatParse.*ParseReference.*RegexpParse.*/m
      str = par.insp
      str.must_match target
    end

    skipit "should fail on the empty input" do
      tree = page5.parse!("")
      tree.must_equal nil
      pf = @page5.parse_fail
      pf.kind_of?(ParseFail).must_equal true
      desc = pf.describe
      puts desc
    end
  end

  describe "short grammar" do
    extend Hipe::Skippy

    def page43
      Grammar.clear_tables!
      @page43 = Grammar.new('short grammar') do |g|
        g.add :list, [:list, '+', :digit]
        g.add :list, [:list, '-', :digit]
        g.add :list, :digit
        g.add :digit, /\A[0-9]+\Z/
      end
      @page43
    end

    skipit "should not infinite loop on spawn" do
      master_blaster = page43.entry(:list)
      spawn = master_blaster.spawn(Context.new)
    end

    skipit "should fail on the empty input" do
      tree = @page43.parse!("")
      tree.must_equal nil
      pf = @page43.parse_fail
      pf.kind_of?(ParseFail).must_equal true
      desc = pf.describe
      puts desc
    end
  end
end
