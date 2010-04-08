require 'diff/lcs'

class String
  def unmarginalize! n=nil
    n ||= /\A *(?! )/.match(self)[0].length
    gsub!(/(?:^ {#{n}}|\n\Z)/, '')
  end
  def one_line!
    gsub!(/\n/,' ')
  end
  def stack_method
    (/`([^']+)'$/ =~ self ) ? $1 : '<unknown method>'
  end
end

module Hipe
  module Parsie
    module SpecExtension
      def skipit msg, &b; puts "skipping: #{msg}" end
      def skipbefore &b; end
      def self.extended obj
        obj.send(:include, SpecInstanceMethods)
      end
    end

    module SpecInstanceMethods
      def with it
        yield it
      end
      def assert_array tgt, arr, msg=nil
        if tgt == arr
          assert_equal tgt, arr
        else
          msg = msg.nil? ? nil : "#{msg} - "
          if arr.kind_of? Array
            diff = Diff::LCS.diff(tgt, arr)
            puts("\nFrom "<< caller[0].stack_method)
            puts diff.to_yaml
            assert(false, "array equal failed. see diff")
          else
            assert(false, "#{msg}was not array: #{arr.insp}")
          end
        end
      end
      def assert_string tgt, str, msg=nil
        if tgt == str
          assert_equal tgt, str
        else
          debugger
          msg = msg.nil? ? nil : "#{msg} - "
          if str.kind_of? String
            l, r = [tgt,str].map{|x| x.split(' ')}
            diff = Diff::LCS.diff(l, r)
            puts("\nassert_string failure from "<< caller[0].stack_method << ':')
            puts diff.to_yaml
            assert(false, "#{msg}str equal failed. see diff")
          else
            msg = msg.nil? ? nil : "#{msg} - "
            assert(false, "#{msg}was not string: #{str.insp}")
          end
        end
      end
    end

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

    [StringParse, RegexpParse, UnionParse, ConcatParse,RangeParse].each do |x|
      x.send(:include, ParseTestAssertions)
    end

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
