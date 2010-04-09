require 'minitest/autorun'
require 'ruby-debug'

addme = File.expand_path('../../lib',__FILE__)
$:.unshift(addme) unless $:.include?(addme)
require 'man-parse'

class String
  def unmarginalize! n=nil
    n ||= /\A *(?! )/.match(self)[0].length
    gsub!(/^ {#{n}}/, '')
    gsub!(/\n\Z/,'') # remove one trailing newline, b/c this is so common
  end
  def one_line!
    gsub!(/\n/,' ')
    self
  end
  def stack_method
    (/`([^']+)'$/ =~ self ) ? $1 : '<unknown method>'
  end
end

class MiniTest::Spec < MiniTest::Unit::TestCase
  def assert_equal_array exp, act, msg=nil
    msg = message(msg) do
      require 'diff/lcs'
      if act.kind_of? Array
        diff = Diff::LCS.diff(exp, act)
        my_msg = "Arrays were not equal. Diff:\n"
        my_msg += diff.to_yaml.gsub(/ *$/,'')
        my_msg
      else
        "Expected Array had %s" % [ act.class ]
      end
    end
    assert(exp == act, msg)
  end
  def assert_equal_string exp, act, msg=nil
    msg = message(msg) do
      require 'diff/lcs'
      if act.kind_of? String
        left, right = [exp, act].map{|x| x.split(' ')}
        diff = Diff::LCS.diff(left, right)
        my_msg = "Strings were not equal. Diff:\n"
        my_msg += diff.to_yaml.gsub(/ *$/,'')
        my_msg
      else
        "Expected String had %s" % [ act.class ]
      end
    end
    assert(exp == act, msg)
  end
end
