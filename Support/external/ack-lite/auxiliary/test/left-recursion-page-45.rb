require File.dirname(__FILE__)+'/support/common-setup.rb'

module Hipe::Parsie
  describe "left recursion page 45" do
    extend SpecExtension

    def page43
      name = 'page43'
      Grammar.all.has?(name) ? Grammar.all[name] :
        Grammar.new(name) do |g|
          g.add :list, [:list, '+', :digit]
          g.add :list, [:list, '-', :digit]
          g.add :list, :digit
          g.add :digit, /\A[0-9]+\Z/
          g.test_context = self
        end
    end

    it "should build the grammar (1)" do
      assert_kind_of Grammar, page43
    end

    it "should none (2)" do
      page43.parse!("").must_fail("expecting digit and had no input")
    end

    it "should bad (3)" do
      page43.parse!("foo").must_fail("expecting digit near \"foo\"")
    end

    it "should good (4)" do
      p = page43.parse!("1")
      p.done?.must_equal false
      p.ok?.must_equal true
      p.tree.must(:regexp, :digit){|v| v.must_equal "1" }
    end

    it "should good bad (5)" do
      page43.parse!("foo").must_fail("expecting digit near \"foo\"")
    end

    it "should good good be bad (6)" do
      page43.parse!("1\n+").must_fail(
        "expecting digit at end of input near \"+\""
      )
    end

    it "should good good be bad (7)" do
      page43.parse!("1\n-").must_fail(
        "expecting digit at end of input near \"-\""
      )
    end

    it "should good bad (8)" do
      page43.parse!("1\n2").must_fail(
        "expecting \"+\" or \"-\" near \"2\""
      )
    end

    it "should good good bad (9)" do
      page43.parse!("1\n+\nfoo").must_fail(
        "expecting digit near \"foo\""
      )
    end

    it "shoud good good good (10)" do
      parse = page43.parse!("1\n+\n2")
      parse.ok?.must_equal true
      parse.unparse.must_equal ["1", "+", "2"]
      tree = parse.tree
      tree.must(:concat,:list) do |arr|
        arr[0].must(:regexp, :digit){|v| v.must_equal '1'}
        arr[1].must(:string,  nil  ){|v| v.must_equal '+'}
        arr[2].must(:regexp, :digit){|v| v.must_equal '2'}
      end
    end

    it "should good good good bad (11)" do
      parse = page43.parse!("1\n+\n2\n3")
      parse.must_fail("expecting \"+\" or \"-\" near \"3\"")
    end

    it "should good good good good (bad) (12)" do
      parse = page43.parse!("1\n+\n2\n+")
      parse.must_fail("expecting digit at end of input near \"+\"")
    end

    it "should do good 2 operators (13)" do
      parse = page43.parse!("1\n+\n2\n+\n3")
      parse.unparse.must_equal ["1", "+", "2", "+", "3"]
      parse.tree.must(:concat,:list) do |arr|
        arr[0].must(:concat, :list) do |arr2|
          arr2[0].must(:regexp, :digit){|v| v.must_equal '1'}
          arr2[1].must(:string,  nil  ){|v| v.must_equal '+'}
          arr2[2].must(:regexp, :digit){|v| v.must_equal '2'}
        end
        arr[1].must(:string,nil) {|v| v.must_equal '+'}
        arr[2].must(:regexp,:digit) {|v| v.must_equal '3'}
      end
    end
  end
end
