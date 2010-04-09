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
      #
      # a lot of this may be supported by minitest already somehow,
      # but we just didn't have the time to figure it out
      #
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
          # debugger
          msg = msg.nil? ? nil : "#{msg} - "
          if str.kind_of? String
            l, r = [tgt,str].map{|x| x.split(' ')}
            diff = Diff::LCS.diff(l, r)
            puts("\nassert_string failure from "<<
              caller[0].stack_method << ':'
            )
            puts diff.to_yaml
            assert(false, "#{msg}str equal failed. see diff")
          else
            msg = msg.nil? ? nil : "#{msg} - "
            assert(false, "#{msg}was not string: #{str.insp}")
          end
        end
      end
    end
  end
end
