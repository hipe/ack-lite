require File.dirname(__FILE__)+'/support/common-setup.rb'

module Hipe
  module Parsie
    describe StackeyStream do
      it "(2-1-1) should work when we push" do

        # operations that change the state of the thing
        # are the first lines in a groups below
        fh = File.open(File.dirname(__FILE__)+'/data/4-lines.txt')
        StackeyStream.enhance(fh)
        fh.peek.must_equal          "orig line 1"
        fh.token_at(0).must_equal   "orig line 1"
        fh.pop.must_equal           "orig line 1"

        fh.peek.must_equal          "orig line 2"
        fh.token_at(1).must_equal   "orig line 2"
        fh.token_at(0).must_equal   "orig line 1"
        fh.pop.must_equal           "orig line 2"
        fh.token_at(1).must_equal   "orig line 2"
        fh.token_at(0).must_equal   "orig line 1"


        fh.push                     "pushed once"
        fh.peek.must_equal          "pushed once"
        fh.token_at(0).must_equal   "orig line 1"
        fh.token_at(1).must_equal   "pushed once"

        fh.push                     "pushed twice"
        fh.peek.must_equal          "pushed twice"
        fh.token_at(0).must_equal   "pushed twice"
        fh.token_at(1).must_equal   "pushed once"
        fh.token_at(2).must_equal   "orig line 3"

        fh.push                     "pushed thrice"
        fh.peek.must_equal          "pushed thrice"
        fh.token_at(-1).must_equal  "pushed thrice" # sure why not

        fh.pop.must_equal           "pushed thrice"
        fh.pop.must_equal           "pushed twice"
        fh.pop.must_equal           "pushed once"
        fh.pop.must_equal           "orig line 3"
        fh.pop.must_equal           "orig line 4"
        fh.pop.must_equal           nil

        fh.token_at(-1).must_equal  "pushed thrice"
        fh.token_at(0).must_equal   "pushed twice"
        fh.token_at(1).must_equal   "pushed once"
        fh.token_at(2).must_equal   "orig line 3"
        fh.token_at(3).must_equal   "orig line 4"
        fh.token_at(5).must_equal    nil

        # fh.push "second push"
        # fh.offset.must_equal 2
      end
    end
  end
end
