module Hipe

  module Parsie

    class Cfg

      def parse! mixed
        ctxt = ParseContext.new
        tokenizer = build_tokenizer mixed
        parse = build_start_parse ctxt
        while ( ! parse.done? ) && ( token = tokenizer.peek )
          ctxt.tic
          resp = parse.look token
          if 0 != WANTS & resp
            parse.take! token
            tokenizer.pop!
          else
            break
          end
          break if parse.done?
        end
        if ! parse.ok?
          pf = ParseFail.new(tokenizer, parse)
        elsif tokenizer.has_more_tokens?
          pf = ParseFail.new(tokenizer, parse)
        else
          pf = nil
        end
        parse.fail = pf if pf
        parse
      end

    end


    class StringLinesTokenizer
      # this is a sandbox for experimenting with tokenizer interface,
      # for use possibly in something more uselful like in input stream
      # tokenizer
      # note that in lemon the lexer calls the parser

      attr_accessor :has_more_tokens
      def initialize str
        @lines = str.split("\n")
        @offset = -1;
        @last_offset = @lines.length - 1
      end
      def peek
        hypothetical = @offset + 1
        return nil if hypothetical > @last_offset
        @lines[hypothetical]
      end
      def pop!
        return nil if @offset > @last_offset
        @offset += 1 # let it get one past last offset
        @lines[@offset]
      end
      def has_more_tokens?
        @offset < @last_offset # b/c pop is the only way to go
      end
      def describe
        # assume there was peeking
        use_offset = @offset + 1
        if use_offset == -1
          "at beginning of input"
        elsif use_offset > @last_offset
          if @lines.length == 0
            "and had no input"
          else
            "at end of input near "+@lines[@last_offset].inspect
          end
        else
          "near \""+@lines[use_offset]+'"'
        end
      end
    end

    # context-free grammar, also variously called a 'table' and 'gramar' here
    # experimentally, it is also the parser (but not the parse)
    class Cfg

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
        yield self
      end

      def symbol name
        @symbols.retrieve name
      end

      # adds a production rule, merging it into
      # or creating a union if necessary
      def add symbol_name, mixed
        @start_symbol_name = symbol_name if @symbols.size == 0
        prod = build_production mixed
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

      def add_prod prod
        unless prod.kind_of? Productive
          $prod = prod
          no('wtf u tried to add $prod as a production')
        end
        @productions << prod
      end

      # the argument is given a default just for testing
      def build_start_parse ctxt= ParseContext.new
        symbol(@start_symbol_name).build_parse(ctxt)
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

      def build_production mixed, allowed = nil
        if allowed
          unless allowed.detect{|x| mixed.kind_of? x }
            raise ParseParseFail.new("can't use #{mixed.class.inspect} here")
          end
        end

        prod =
        case mixed
          when Regexp; RegexpProduction.new(mixed)
          when Symbol; SymbolReference.new(mixed)
          when Array;  ConcatProduction.new(self, mixed)
          when String; StringProduction.new(mixed)
          else raise ParseParseFail.new("no: #{mixed.inspect}")
        end
        prod.production_id = Productions.register(prod)
        prod
      end

      def build_tokenizer mixed
        case mixed
        when String; StringLinesTokenizer.new(mixed)
        else raise ParseParseFail.new("no: #{mixed.inspect}")
        end
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
    end
    Grammar = Cfg       # external alias for readability
  end
end
