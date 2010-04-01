require File.dirname(__FILE__)+'/support/common-setup.rb'

module Hipe::Parsie
  describe "union basic" do
    extend SpecExtension

    def string_or_re
      name = 'string or re'
      Grammar.all.has?(name) ? Grammar.all[name] :
        Grammar.new(name) do |g|
          g.add "string or regexp", 'abc123'
          g.add "string or regexp", /^[a-z]+[0-9]+$/
          g.test_context = self
        end
    end

    it "should fail on the empty input (1)" do
      string_or_re.must_fail("",
        "expecting \"abc123\" or string or regexp and had no input")
    end

    it "should fail on bad string (2)" do
      string_or_re.must_fail("123abc",
        "expecting \"abc123\" or string or regexp near \"123abc\"")
    end

    it "should parse on one good string using string symbol (3)" do
      parse = string_or_re.parse!("abc123")
      parse.failed?.must_equal false
      assert_kind_of UnionParse, parse
      parse.done?.must_equal true
      parse.tree.must :string, "string or regexp" do |v|
        v.must_equal "abc123"
      end
    end

    it "should parse on one good string using regex symbol (4)" do
      parse = string_or_re.parse!("def789")
      parse.failed?.must_equal false
      parse.done?.must_equal true
      parse.tree.must :regexp, "string or regexp" do |v|
        v.must_equal "def789"
      end
    end

    def minimal_union
      name = 'minimal union'
      Grammar.all.has?(name) ? Grammar.all[name] :
        Grammar.new(name) do |g|
          g.add :item, 'foo'
          g.add :item, 'bar'
        end
    end

    it "minimal union should know what's what after a parse (5)" do
      parse = minimal_union.parse!("foo")
      parse.done?.must_equal true
      parse.ok?.must_equal true
    end
  end
end
