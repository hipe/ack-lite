require 'minitest/autorun'  # unit and spec
module Hipe
  module AckLite
  end
  describe AckLite do
    it "should pass" do
      1.must_equal 1
    end
    it "should fail" do
      1.must_equal 2
    end
  end
end
