require File.dirname(__FILE__)+'/support/bare-setup.rb'
require File.expand_path('../../lib/parsie/general-support.rb', __FILE__)

module Foo
  MetaTools = Hipe::Parsie::MetaTools
  describe MetaTools do

    it "should add accessor (meta-tools-1)" do
      str = 'str'
      assert_equal(false, str.respond_to?(:singleton_class),
        'if this fails on 1.9 that\'s ok to remove it'
      )
      MetaTools.enhance(str)
      assert_equal(true, str.respond_to?(:singleton_class), 'added method')
      sing = class << str; self end
      str.singleton_class.must_equal sing
    end

    it "define method should work on the object (meta-tools-2)" do
      str = 'foo'
      MetaTools.enhance(str)
      assert_equal(false, str.respond_to?(:bar))
      some_var = 'some value never see'
      str.singleton_class.define_method!(:baz){some_var}
      some_var = 'some value'
      assert_equal(true, str.respond_to?(:baz))
      assert_equal('some value', str.baz)
    end

    it "raises when attempt to redefine (meta-tools-3)" do
      str = MetaTools['foo']
      str.singleton_class.define_method!(:baz){'foo'}
      assert_raises RuntimeError do
        str.singleton_class.define_method!(:baz){'whatever'}
      end
    end
  end
end
