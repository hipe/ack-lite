require File.dirname(__FILE__)+'/support/common-setup.rb'

module Hipe::Parsie
  describe "left recursion basic" do
    extend SpecExtension

    def digits
      name = 'digits'
      Grammar.all.has?(name) ? Grammar.all[name] :
        Grammar.new(name) do |g|
          g.add :list, [:list, :digit]
          g.add :list, :digit
          g.add :digit, /\A[0-9]+\Z/
          g.reference_check
          g.test_context = self
        end
    end

    it "must build the grammar (1)" do
      g = digits
      assert_kind_of(Grammar, g)
    end

    it "must do to_bnf (2)" do
      g = Grammar.new('grammar for bnf') do |g|
        g.add :list, [:list, :digit]
        g.add :list, :digit
        g.add :digit, /\A([0-9]+)\Z/
        g.test_context = self
      end
      target = <<-'HERE'.unmarginalize!(6)
        list   ::=  list digit.
        list   ::=  digit.
        digit  ::=  /\A([0-9]+)\Z/.
      HERE
      str = g.to_bnf
      str.must_equal target
    end

    it "must validate_down and ins() (2-2)" do
      grammar = self.digits
      parse = grammar.build_start_parse
      RootParse.ui_push
      RootParse.validate_down
      str = RootParse.ui_pop
      tgt = /\A      ok.*\n    ok.*\n    ok.*\n  ok.*\Z/
      assert_match(tgt, str)

      RootParse.ui_push
      RootParse.ins
      str = RootParse.ui_pop
      tgt = /\A\s{0}[^ ].+\n {2}[^ ].+\n {4}[^ ].+\n {6}[^ ].+\n {6}[^ ].+\n {4}[^ ].+\Z/
      assert_match(tgt, str)
    end

    it "should do inspct (3)" do
      grammar = self.digits
      parse = grammar.build_start_parse
      tgt = /.*UnionParse.*ConcatParse.*RecursiveReference.*RegexpParse.*/m
      str = parse.inspct
      assert_match(tgt, str)
    end

    it "should do empty (4)" do
      digits.parse!("").must_fail(
        "expecting digit and had no input"
      )
    end

    it "should do bad (5)" do
      digits.parse!("abc").must_fail(
        "expecting digit near \"abc\""
      )
    end

    it "should do good (6)" do
      parse = digits.parse!("123")
      parse.tree.must(:regexp, :digit){|v| v.must_equal "123" }
    end

    it "should do good bad (7)" do
      digits.parse!("123\nabcd").must_fail("expecting digit near \"abcd\"")
    end

    it "should do good good (8)" do
      parse = digits.parse!("123\n456")
      parse.tree.must(:concat, :list) do |arr|
        arr[0].must(:regexp, :digit){|v| v.must_equal "123"}
        arr[1].must(:regexp, :digit){|v| v.must_equal "456"}
      end
    end

    it "should do good good bad (9)" do
      parse = digits.parse!("123\n456\nabc").must_fail(
        "expecting digit near \"abc\""
      )
    end

    it "should do good good good (10)" do
      parse = digits.parse!("123\n456\n789")
      parse.done?.must_equal false
      parse.ok?.must_equal true
      parse.tree.must(:concat, :list) do |arr|
        arr[0].must(:concat, :list) do |arr1|
          arr1[0].must(:regexp, :digit){|v| v.must_equal "123"}
          arr1[1].must(:regexp, :digit){|v| v.must_equal "456"}
        end
        arr[1].must(:regexp, :digit){|v| v.must_equal "789"}
      end
    end

    it "should do good good good bad (11)" do
      parse = digits.parse!("123\n456\n789\nfoo").must_fail(
        "expecting digit near \"foo\""
      )
    end

    it "should do good good good good (12)" do
      parse = digits.parse!("123\n456\n789\n101112")
      parse.done?.must_equal false
      parse.ok?.must_equal true
      parse.unparse.must_equal ["123", "456", "789", "101112"]
    end

    it "should do good good good good bad (13)" do
      parse = digits.parse!("11\n22\n33\n44\nfoo").must_fail(
        "expecting digit near \"foo\""
      )
    end

    it "should do good good good good good (14)" do
      parse = digits.parse!("11\n22\n33\n44\n55")
      parse.done?.must_equal false
      parse.ok?.must_equal true
      parse.unparse.must_equal ["11", "22", "33", "44", "55"]
    end
  end
end
