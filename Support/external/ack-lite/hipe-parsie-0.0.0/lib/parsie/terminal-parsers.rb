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
      def is_nil_parse?
        false
      end
      def is_reference?
        false
      end
      # needs childable below
      def ins
        ui.puts "#{indent}#{short}#{short_matched}"
      end
      def validate_down
        if (depth != parent.depth+1)
          no("#{short} has bad depth")
        end
        ui.puts "#{indent}ok down TERMINAL stop (depth: #{depth})#{short}"
      end
    end


    class StopParse
      include TerminalParsey
      def initialize prod, ctxt, parent, opts
        @opts = opts # almost always throwaway empty
        @production_id = prod
        @context_id = ctxt.context_id
        self.parent_id = parent.parse_id
      end
      def look token
        (SATISFIED | WANTS)
      end
      def take! token
        parse_context.stop_parse!(self)
        (SATISFIED | WANTS)
      end
      def tree
        @tree ||= begin
          ParseTree.new(:string, :stop, @production_id, :stop)
        end
      end
    end

    class StringParse
      include TerminalParsey
      def initialize prod, ctxt, parent, _
        self.parent_id = parent.parse_id
        @string = prod.string_literal
        @production_id = prod.production_id
        @done = false
        @ok = false
      end
      def parse_type; :string end
      def parse_type_short; 'str' end
      def clear_self!
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
      def short_matched
        (@ok && @done) ? ":\"#{@string}\"" : ''
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
      def initialize production, ctxt, parent, re_opts
        self.parent_id = parent.parse_id
        @production_id = production.production_id
        @context_id = ctxt.context_id
        @symbol_name = production.symbol_name
        @md = false
        @re = production.re
        @re_opts = re_opts
        @done = false
        @ok = false    # @todo some regexs will be zero width
      end
      def parse_type; :regexp end
      def parse_type_short; 're' end
      def clear_self!
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
      def short_matched
        (@ok && @done) ? "\"#{@md[0]}\"" : ''
      end
      def _unparse arr
        no("no") unless @ok
        arr << @md[0]
        nil
      end
      def tree
        return @tree unless @tree.nil? # yes
        @tree = begin
          if @md.nil?
            false
          else
            val =
            if @md.captures.empty?
              @md[0]
            elsif @re_opts[:named_captures]
              Hash[@re_opts[:named_captures].zip(@md.captures)]
            elsif @md.captures.size == 1
              @md.captures[0]
            else
              @md.captures
            end
            ParseTree.new(:regexp, @symbol_name, @production_id, val)
          end
        end
        @tree
      end
    end
  end
end
