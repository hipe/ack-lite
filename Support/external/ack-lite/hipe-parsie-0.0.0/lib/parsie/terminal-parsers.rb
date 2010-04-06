module Hipe
  module Parsie

    module TerminalParsey
      include Parsey, Inspecty, Childable

      def production
        Productions[@production_id]
      end
      def symbol_name
        production.respond_to?(:symbol_name) ?
          production.symbol_name : nil
      end
      def symbol_name_for_debugging
        symbol_name
      end
      def release!
        procution.release self
      end
      def can_have_children?
        false
      end
      def nil_parse?
        false
      end
      def is_reference?
        false
      end
      # needs childable below
      def ins
        ui.puts "#{indent}#{short}"
      end
      def validate
        if (depth != parent.depth+1)
          no("#{short} has bad depth")
        end
        ui.puts "#{indent}ok (depth: #{depth})#{short}"
      end
    end

    class StringParse
      include TerminalParsey
      def initialize prod, ctxt, parent
        self.parent_id = parent.parse_id
        @string = prod.string_literal
        @production_id = prod.production_id
        @done = false
        @ok = false
      end
      def parse_type; :string end
      def parse_type_short; 'str' end
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
        SATISFIED | WANTS
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
        unless @ok
          debugger
          'x'
          no('no')
        end
        arr.push @string
        nil
      end
    end

    class PushBack
      attr_reader :string
      def initialize str
        @string = str
      end
    end

    class RegexpParse
      include TerminalParsey
      attr_accessor :md
      def initialize production, ctxt, parent
        self.parent_id = parent.parse_id
        @production_id = production.production_id
        @symbol_name = production.symbol_name
        @md = false
        @re = production.re
        @done = false
        @ok = false    # @todo some regexs will be zero width
      end
      def parse_type; :regexp end
      def parse_type_short; 're' end
      def reset!
        @parent_id = nil
        @done = @ok = @md = false
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
        @md = @re.match(str)
        no "won't take if no match" unless @md
        if @md.post_match.length > 0
          parent.bubble_up PushBack.new(@md.post_match)
        end
        @done = true
        @ok = true
        SATISFIED | WANTS
      end
      def inspct _,o=nil;
        blah = @md ? (@md.length > 1 ? @md.captures.inspect :
        @md.inspect ) : @md.inspect
        s = sprintf(("#<RegexpParse @done=%s "<<
          " @ok=%s @md=%s @symbol_name=%s"),
          @done.inspect, @ok.inspect,
          blah, @symbol_name.inspect)
        s
      end
      def _unparse arr
        no("no") unless @ok
        arr << @md[0]
        nil
      end
      def tree
        return @tree unless @tree.nil?
        @tree = begin
          if ! @md then false
          else
            val = @md.captures.length > 0 ?
              @md.captures : @md[0]
            ParseTree.new(:regexp, @symbol_name, @production_id, val)
          end
        end
        @tree
      end
    end
  end
end
