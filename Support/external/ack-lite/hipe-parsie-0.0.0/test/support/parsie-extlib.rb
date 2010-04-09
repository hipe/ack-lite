module Hipe
  module Parsie
    module ParseTestAssertions
      attr_accessor :test_context
      def must_fail expected_msg
        failed?.must_equal true
        fail = self.fail
        test_context.assert_kind_of ParseFail, fail
        desc = fail.describe
        desc.must_equal expected_msg
      end
    end

    [StringParse, RegexpParse, UnionParse, ConcatParse,
    RangeParse].each{|x|x.send(:include, ParseTestAssertions)}

    class Cfg
      attr_accessor :test_context
      def must_fail input_string, expected_msg
        grammar = self
        parse = grammar.parse! input_string
        parse.test_context = test_context
        parse.must_fail expected_msg
      end
      def satisfied_and_final_offset_must_be sat, final
        parse = build_start_parse
        have_sat = parse.satisfied_offset
        have_fin = parse.final_offset
        test_context.assert_equal(sat, have_sat, "satisfied offset")
        test_context.assert_equal(final, have_fin, "final offset")
      end
    end

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
  end
end