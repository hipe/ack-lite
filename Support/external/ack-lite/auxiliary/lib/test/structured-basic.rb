require 'minitest/autorun'  # unit and spec
require 'ruby-debug'
root = File.expand_path('..',File.dirname(__FILE__))
require "#{root}/parsie.rb"
require "#{root}/test/helpers.rb"

module Hipe::Parsie
  describe "structured basic" do
    extend SpecExtension
    def grammar
      name = 'i really like her'
      if Grammar.all.has?(name) then Grammar.all[name]
      else Grammar.new(name) do |g|
          g.add :sentence, [:subject,:adjective,'like',:object,:adj2]
          g.add :subject, 'i'
          g.add :subject, 'you'
          g.add :adjective, 'really'
          g.add :adjective, []
          g.add :object, 'her'
          g.add :object, 'him'
          g.add :adj2, []
          g.add :adj2 ,['a','lot']
          g.test_context = self
        end        
      end
    end
    
    it "no input (1)" do
      grammar.must_fail("", "expecting \"i\" or \"you\" and had no input")
    end
    
    it "one bad token (2)" do 
      grammar.must_fail("me", "expecting \"i\" or \"you\" near \"me\"")      
    end
    
    it "one good token (3)" do 
      grammar.must_fail("i", 
        "expecting \"really\" or \"like\" at end of input near \"i\""
      )      
    end
    
    it "one good one bad (4)" do 
      grammar.must_fail(
        "i\ndon't", 
        "expecting \"really\" or \"like\" near \"don't\""
      )      
    end
    
    it "use optional adjective (5)" do
      grammar.must_fail(
        "i\nreally", 
        "expecting \"like\" at end of input near \"really\""
      )
    end    
    
    it "jump over optional adjective (6)" do
      grammar.must_fail(
        "i\nlike", 
        "expecting \"her\" or \"him\" at end of input near \"like\""
      )
    end
    
    it "should be same as above whether or not you use the (7)" do 
      grammar.must_fail(
        "i\nreally\nlike", 
        "expecting \"her\" or \"him\" at end of input near \"like\""
      )
    end  
  
    it "use bad object (8)" do
      grammar.must_fail(
        "i\nlike\nit", 
        "expecting \"her\" or \"him\" near \"it\""
      )
    end
    
    it "see if you can complete it (9)" do
      parse = grammar.parse!("i\nreally\nlike\nhim")
      parse.tree.must(:concat, :sentence) do |arr|
        arr[0].must(:string, :subject){|v| v.must_equal "i" }
        arr[1].must(:string, :adjective){|v| v.must_equal "really" }
        arr[2].must(:string, nil){|v| v.must_equal "like" }
        arr[3].must(:string, :object){|v| v.must_equal "him"}
      end
    end
    
    def trailing_opts
      name = 'trailing opts'
      if Grammar.all.has?(name) then Grammar.all[name]
      else Grammar.new(name) do |g|
          g.add :sentence, ["go", :adj]
          g.add :adj, []
          g.add :adj, "away"
          g.test_context = self
        end        
      end
    end
    
    it "trailing options (10)" do
      # Debug.look = true
      # Debug.true = true
      trailing_opts.must_fail(
        "go\nthere",
        "expecting \"away\" near \"there\""
      )
    end
    
    it "trailing bad option (11)" do
      grammar.must_fail(
        "i\nreally\nlike\nhim\ntons",
        "expecting \"a\" near \"tons\""
      )
    end
    
    it "trailing bad option again (12)" do
      grammar.must_fail(
        "i\nreally\nlike\nhim\na\nton",
        "expecting \"lot\" near \"ton\""
      )
    end
    
    it "good parse again (13)" do
      parse = grammar.parse!("i\nreally\nlike\nhim\na\nlot")
      parse.tree.must(:concat, :sentence) do |arr|
        arr[0].must(:string, :subject){|v| v.must_equal "i" }
        arr[1].must(:string, :adjective){|v| v.must_equal "really" }
        arr[2].must(:string, nil){|v| v.must_equal "like" }
        arr[3].must(:string, :object){|v| v.must_equal "him"}
        arr[4].must(:concat, :adj2) do |arr2|
          arr2[0].must(:string,nil){|v| v.must_equal "a" }
          arr2[1].must(:string,nil){|v| v.must_equal "lot" }          
        end
      end
    end  
  end  
end
