module Hipe
  module Parsie
    class RangeParse
      include NonterminalParsey
      attr_reader :parse_id
      def initialize prod, ctxt, parent, opts, my_opts
        @parse_id = Parses.register self
        self.parent_id = parent.parse_id
        @num_satisfied = 0
        @parses_satisfied = []
        @context_id = ctxt.context_id
        @my_production_id = prod.production_id
        @passthru_opts = opts
        @opts = my_opts
        @range = prod.range
        new_current!
      end
      def parse_type; :range end
      def parse_type_short; 'r' end
      def my_production; Productions[@my_production_id] end
      def symbol_name;
        my_production.respond_to?(:symbol_name) ?
          my_production.symbol_name : false
      end
      def update_current_to_reflect_decision! d
        no('no') if d.current_wants?
        no('no') unless d.next_wants?
        no('no') unless current.ok?
        new_current!
        nil
      end
      def new_current!
        if (false==@opts[:capture])
          if @new_current_called
            no("only call this once when no capture")
          end
          @new_current_called = true
        end
        @current_parse_id = nil
        @current_parse = nil
        parse = pop_next
        if parse.respond_to? :parse_id
          @current_parse_id = parse.parse_id
        else
          @current_parse = parse
        end
        nil
      end
      def peek_next
        @peek_next ||= begin
          parse = my_production.child_production.build_parse(
            parse_context, self, @passthru_opts
          )
          parse
        end
      end
      def pop_next
        peek_next
        resp = @peek_next
        @peek_next = nil
        resp
      end
      def current
        @current_parse_id ? Parses[@current_parse_id] : @current_parse
      end
      def expecting
        current.expecting
      end
      def num_satisfied
        @num_satisfied
      end
      def ok?
        num_satisfied >= @range.begin
      end
      def is_last? num
        @range.end != -1 && num >= @range.end
      end
      def done?
        @range.end != -1 && num_satisfied == @range.end
      end
      def look foo
        Debug.puts "#{indent}#{short}.look #{foo.inspect}" if Debug.verbose?
        @last_look = foo
        d = decision(foo)
        if Debug.verbose?
          Debug.puts("#{indent}#{short}.look #{foo.inspect} was: " <<
          d.inspct_for_debugging)
        end
        d.response
      end
      class Decision
        extend AttrAccessors
        boolean_accessor :wants, :satisfied, :open, :current_wants,
          :next_wants
        attr_accessor :next_child_response
        include Decisioney
        def short
          them = %w(wants satisfied open)
          "("<<(them.map{|x| desc_bool(x)}*', ')<<")"
        end
      end
      def decision foo
        no("won't make decision when done") if done?
        child_resp = Response[current.look(foo)]
        d = Decision.new
        num = num_satisfied
        if child_resp.wants?
          d.wants = true
          d.current_wants = true
          if child_resp.satisfied?
            num += 1
            if child_resp.open?
              d.open = true
            else
              d.open = ! is_last?(num)
            end
          else
            d.open = true # assume etc
          end
        else
          d.current_wants = false
          if child_resp.satisfied?
            if is_last? num
              d.wants = false
              d.open = false
            else
              resp2 = Response[peek_next.look(foo)]
              d.next_child_response = resp2
              if resp2.wants?
                d.next_wants = true
                d.wants = true
                if resp2.satisfied?
                  num += 1
                  if resp2.open?
                    d.open = true
                  else
                    d.open = ! is_last?(num)
                  end
                else
                  d.open = true
                end
              else
                d.next_wants = false
                d.wants = false
                d.open = ! done?
              end
            end
          else
            d.wants = false
            d.open = ! done?
          end
        end
        d.satisfied = num >= @range.begin
        d.assert_complete
        d
      end

      def last_satisfied
        @parses_satisfied.size == 0 ? nil :
        (@parses_satisfied.last.kind_of?(Fixnum) ?
          Parses[@parses_satisfied.last] :
          @parses_satisfied.last
         )
      end

      def push_satisfied parse
        @parses_satisfied.push(
          parse.respond_to?(:parse_id) ? parse.parse_id : parse
        )
        if (false == @opts[:capture])
          def self.push_satisfied(p)
            no("this should only be called once when not capturing!")
          end
        end
      end

      def take! foo
        puts "#{indent}#{short}.take! #{foo.inspect}" if Debug.verbose?
        d = decision(foo)
        unless d.wants?
          no("can't take what i don't want")
        end
        unless d.current_wants?
          update_current_to_reflect_decision!(d)
        end
        child_resp = Response[current.take!(foo)]
        if child_resp.satisfied?
          if last_satisfied != current
            push_satisfied current
            @num_satisfied += 1
          end
          if ! child_resp.open?
            if false==@opts[:capture]
              current.reset!
              if @tic
                @num_satisfied += 1
              else
                @tic = true
              end # suck
            else
              new_current!
            end
          end
        else
          # if child not satisfied, just stay
        end
        d.response
      end

      def _unparse arr
        if false == @opts[:capture]
          arr << :no_capture
        else
          parses_satisfied.each do |p|
            p._unparse arr
          end
        end
      end

      def each_existing_child &block
        parses_satisfied.each_with_index do |child, idx|
          block.call(child, idx)
        end
        nil
      end

      def inspct(ic=InspectContext.new, opts={})
        my_indent = ic.indent
        ic.indent_indent!
        s = sprintf("#<RangeParse:%d",parse_id)
        ll = []
        ll << desc_bool('ok?')
        ll << desc_bool('done?')
        ll << sprintf("symbol_name=%s",symbol_name_for_debugging)
        inspct_attr(ll,%w(@num_satisfied @last_look))
        s << ' ' << ( ll * ' ' )
        ll = [s]
        if last_satisfied_parse != current
          ll << ("current -> " <<
            (current.nil? ? 'nil' : current.inspct(ic, opts))
          )
        end
        ll << "parses_satisfied(#{@parses_satisfied.size}) -> ["
        parses_satisfied.each do |p|
          ll << p.inspct(ic, opts)
        end
        s2 = (ll * "\n#{my_indent}") << ']'

        s2
      end

      def parses_satisfied
        enum = Object.new
        meta = class << enum; self end
        meta.send(:include, Enumerable)
        arr = @parses_satisfied
        me = self
        meta.send(:define_method, :size){ arr.size }
        meta.send(:define_method, :each) do |&block|
          (0..arr.length-1).each do |idx|
            block.call(me.satisfied_parse_at(idx))
          end
        end
        enum
      end

      def last_satisfied_parse
        if @parses_satisfied.any?
          satisfied_parse_at(@parses_satisfied.length - 1)
        else
          nil
        end
      end

      def satisfied_parse_at idx
        mixed = @parses_satisfied[idx]
        object = mixed.kind_of?(Fixnum) ? Parses[mixed] : mixed
        object
      end

      def tree
        if false == @opts[:capture]
          :no_capture
        else
          parses_satisfied.map(&:tree)
        end
      end
    end
  end # end Parsie
end # end Hipe
