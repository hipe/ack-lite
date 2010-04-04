require File.dirname(__FILE__)+'/tokenizers.rb'

module Hipe
  module Parsie
    class Cfg # Context-Free Grammar. (Aliased as 'Grammar' below)
              # it's just a table with productions and symbol references.
              # also variously called a 'table' and 'grammar'.
              # experimentally, it is also the parser (but not the parse)

      include Misc
      @all = Setesque.new
      class << self
        attr_reader :all
        def clear_tables!; @all.clear end
      end

      attr_reader :table_name, :productions, :symbols

      def initialize name, &block
        self.class.all.register(name, self)
        $g = self #shh
        @table_name = name
        @symbols = Setesque.new('symbols'){|id| Productions[id]}
        @productions = []
        @current_add_line = 0
        yield self
      end

      DefaultOpts = Object.new
      class << DefaultOpts
        def notice_stream; $stout end
        def verbose?;      nil    end
      end

      def parse! mixed, opts=DefaultOpts
        process_opts opts
        ctxt = ParseContext.new
        tokenizer = build_tokenizer mixed
        parse = build_start_parse ctxt
        while ( ! parse.done? ) && ( token = tokenizer.peek )
          ctxt.tic!
          $token = token
          if Debug.true?
            Debug.puts "\n\n\nTOKEN: #{token.inspect} (tic #{ctxt.tic})\n\n\n"
          end
          resp = parse.look token
          if 0 != WANTS & resp
            parse.take! token
            tokenizer.pop!  # do a conditional that runs a hook here
            if ctxt.pushback?
              str = ctxt.pushback_pop.string
              Debug.puts "PUSING BACK: #{str}" if Debug.true?
              tokenizer.push str
            end
          else
            break
          end
          break if parse.done?
        end
        if ! parse.ok?
          pf = ParseFail.from_parse_loop(tokenizer, parse)
        elsif tokenizer.has_more_tokens?
          pf = ParseFail.from_parse_loop(tokenizer, parse)
        else
          pf = nil
        end
        parse.fail = pf if pf
        # sux
        parse.test_context = test_context if parse.respond_to? :test_context=
        parse
      end

      def symbol name
        @symbols.retrieve name
      end

      # adds a production rule, merging it into
      # or creating a union if necessary
      def add symbol_name, mixed, opts={}, &block
        @current_add_line += 1
        @start_symbol_name = symbol_name if @symbols.size == 0
        prod = nil
        begin
          prod = build_production mixed, nil, opts, &block
        rescue ParseParseFail=>e
          return parse_parse_fail e, symbol_name, mixed
        end
        add_prod prod
        prod.table_name = @table_name
        prod.symbol_name = symbol_name
        prod_id = prod.production_id
        if ! @symbols.has? symbol_name
          @symbols.register symbol_name, prod_id
        else
          symbol_production = self.symbol(symbol_name)
          if symbol_production.kind_of? UnionSymbol
            union_symbol = symbol_production
            union_symbol.add prod
          else
            @symbols.remove(symbol_name)
            union = UnionSymbol.new(symbol_production)
            prod_id2 = Productions.register union
            add_prod union
            union.symbol_name = symbol_name
            union.production_id = prod_id2
            union.table_name = @table_name
            union.add prod
            @symbols.register(symbol_name, prod_id2)
          end
        end
        nil
      end

      def parse_parse_fail e, symbol_name, mixed
        lines = []
        lines << "in grammar \"#{@table_name}\""
        lines << e.message
        lines << "at production line number #{@current_add_line}"
        lines << "near (#{symbol_name.inspect} --> #{mixed.inspect})"
        msg = lines * ' '
        class << e; self end.send(:define_method, :message) { msg }
        raise e
      end

      def add_prod prod
        unless prod.kind_of? Productive
          $prod = prod
          no('wtf u tried to add $prod as a production')
        end
        @productions << prod
      end

      # the argument is given a default just for testing
      def build_start_parse ctxt= ParseContext.new
        p = symbol(@start_symbol_name).build_parse(ctxt, RootParse)
        p
      end

      def reference_check
        missing = []
        productions.each do |prod|
          err = catch(:ref_fail) do
            prod.reference_check if prod.respond_to? :reference_check
            nil
          end
          missing.concat err[:names] if err
        end
        missing.uniq!
        if missing.length > 0
          adj, s, v, l, r = (missing.length > 1) ?
            ['The following','s','were','(',')'] :
            ['The',          '', 'was','','' ]
          msg = sprintf(
           "%s symbol%s referred to in the \"%s\" grammar %s missing: %s%s%s",
           adj, s, @table_name, v, l, missing.map(&:inspect).join(', '), r
          )
          raise ParseParseFail.new msg
        end
      end

      def build_production mixed, allowed=nil, opts={}, &block
        if allowed
          unless allowed.detect{|x| mixed.kind_of? x }
            raise ParseParseFail.new("can't use #{mixed.class.inspect}"<<
            " here, expecting "<<oxford_comma(allowed.map(&:to_s),' or '))
          end
        end

        prod =
        case mixed
          when Regexp; RegexpProduction.new(mixed)
          when Symbol; SymbolReference.new(mixed)
          when Array;  ConcatProduction.factory(self, mixed, opts, &block)
          when String; StringProduction.new(mixed)
          else raise ParseParseFail.new("no: #{mixed.inspect}")
        end
        prod.production_id = Productions.register(prod)
        prod
      end

      def to_bnf opts={}
        show_pids = opts[:pids]
        prerendered = []
        left_max = 0
        fail = productions.detect{|x| ! x.symbol_name.kind_of? Symbol }
        if fail
          sym_name = fail.symbol_name
          raise ParseParseFail("Must have only symbol names for "<<
          "productions, not #{fail.inspect}")
        end
        productions.each do |p|
          next if p.kind_of? UnionSymbol # depends note1
          strname = p.symbol_name.to_s
          strname = "(##{p.production_id}) #{strname}" if show_pids
          len = strname.length
          left_max = len if len > left_max
          prerendered << [strname, p.to_bnf_rhs]
        end
        col = left_max + 1
        prerendered.map do |row|
          sprintf("  %-#{col}s ::=  %s.", row[0], row[1])
        end * "\n"
      end

    private

      def build_tokenizer mixed
        case mixed
        when String; StringLinesTokenizer.new(mixed)
        else
          if looks_like_stack?(mixed)
            StackTokenizerAdapter[mixed]
          else
            these = doesnt_look_like_stack_because(mixed)
            raise ParseParseFail.new(
              "Can't build tokenizer from  #{mixed.inspect} because "<<
              "it is not a string and it doesn't implement "<<
              oxford_comma(these,' and ')
            )
          end
        end
      end

      %w(
        looks_like_stack?
        doesnt_look_like_stack_because
      ).each do |meth|
        define_method(meth){|*mix| StackTokenizerAdapter.send(meth,*mix) }
      end

      def process_opts opts
        if opts.verbose?
          Debug.true = true
          unless opts.notice_stream.nil?
            Debug.out = opts.notice_stream
          end
        end
      end
    end
    Grammar = Cfg       # external alias for readability
  end
end
