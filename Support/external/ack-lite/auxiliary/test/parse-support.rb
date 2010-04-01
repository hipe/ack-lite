require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"

module Hipe::Parsie
  describe "Hookey" do
    it "should" do
      class Foo
        extend Hookey
        has_hook_once :after_bar!
        attr_accessor :this_is_me
      end

      f = Foo.new
      f.this_is_me = 'howdy!'
      f.hook_once_after_bar! do |caller, x|
        "ok: #{x} from #{caller.this_is_me}"
      end
      child_resp = nil
      num_ran = f.run_hook_onces_after_bar! do |hook|
        child_resp = hook.call(f, 'foo')
      end
      num_ran.must_equal 1
      child_resp.must_equal "ok: foo from howdy!"
    end
  end
end
