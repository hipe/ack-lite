module Hipe
  module Parsie

    module Terminesque
      include Misc, FaileyMcFailerson, StrictOkAndDone, Inspecty, Childable
      def production
        Productions[@production_id]
      end
      def symbol_name
        production.respond_to?(:symbol_name) ?
          production.symbol_name : nil
      end
      def release!
        procution.release self
      end
    end

    class StringParse
      include Terminesque
      def initialize prod
        @string = prod.string_literal
        @production_id = prod.production_id
        @done = false
        @ok = false
      end
      def reset!
        @parent_id = nil
        @done = @ok = false
      end
      def look token
        no "can't look when done" if @done
        (token == @string) ? (SATISFIED | WANTS) : 0
      end
      def take! token
        no "won't take when done" if @done
        resp = look token
        no "won't take when satisfied" if 0 == (SATISFIED & resp)
        @done = true
        @ok   = true
        SATISFIED
      end
      def expecting
        (@ok && @done) ? [] : [@string.inspect]
      end
      def inspct ctxt, o=nil; inspect end
      def tree
        return @value_tree unless @value_tree.nil?
        symbol_name = respond_to?(:symbol_name) ?
          self.symbol_name : nil
        @value_tree =
          if (@done&&@ok)
            ParseTree.new(:string, symbol_name, @production_id, @string)
          else
            false
          end
        @value_tree
      end
      def _unparse arr
        no("no") unless @ok
        arr << @string
        nil
      end
    end

    class RegexpParse
      include Terminesque
      attr_accessor :matches
      def initialize production
        @production_id = production.production_id
        @symbol_name = production.symbol_name
        @matches = false
        @re = production.re
        @done = false
        @ok = false    # @todo some regexs will be zero width
      end
      def reset!
        @parent_id = nil
        @done = @ok = @matches = false
      end
      def expecting
        (@ok && @done) ? [] : [@symbol_name]
      end
      def look str
        no "won't look when done" if @done
        (@re =~ str) ? (SATISFIED | WANTS) : 0
      end
      def take! str
        no "won't take when done" if @done
        @matches = @re.match(str)
        no "won't take if no match" if (!@matches)
        @done = true
        @ok = true
        SATISFIED
      end
      def inspct _,o=nil;
        inspect
      end
      def _unparse arr
        no("no") unless @ok
        arr << @matches[0]
        nil
      end
      def tree
        return @tree unless @tree.nil?
        @tree = begin
          if ! @matches then false
          else
            val = @matches.captures.length > 0 ?
              @matches.captures : @matches[0]
            ParseTree.new(:regexp, @symbol_name, @production_id, val)
          end
        end
        @tree
      end
    end
  end
end
