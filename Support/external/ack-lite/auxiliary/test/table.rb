require File.dirname(__FILE__)+'/support/common-setup.rb'

module Hipe::Parsie
  describe "grammar tables" do
    extend SpecExtension
    it "should raise on unresolved references, singular (1)" do
      e = proc do
        Grammar.clear_tables!
        g = Grammar.new("thingo") do |g|
          g.add :blah, [:there, 'hi', :not_there, 'hello']
          g.add :there, 'foo'
          g.reference_check
        end
      end.must_raise(ParseParseFail)
      target = <<-HERE.gsub(/\n?^ {8}/,'').strip
        The symbol referred to in the "thingo" grammar was missing: :not_there
      HERE
      e.message.must_equal target
    end

    it "should raise on unresolved references, plural (2)" do
      e = proc do
        Grammar.clear_tables!
        g = Grammar.new("thingo") do |g|
          g.add :blah, [:not_there, 'hi', :not_there_either, 'hello']
          g.reference_check
        end
      end.must_raise(ParseParseFail)
      target = <<-HERE.gsub(/\n?^ {8}/,'').strip
        The following symbols referred to in the "thingo" grammar were
         missing: (:not_there, :not_there_either)
      HERE
      e.message.must_equal target
    end

    it "should not raise on unresolved references if not asked to (3)" do
      assert_block do
        Grammar.clear_tables!
        g = Grammar.new("thingo") do |g|
          g.add :blah, [:not_there, 'hi', :not_there_either, 'hello' ]
        end
        true
      end
    end
  end
end
