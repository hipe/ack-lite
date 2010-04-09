# because for now the grammar object is the one that is doing the parsing,
# it is responsible for loading the necessary tokenizers:
#
require File.dirname(__FILE__)+'/tokenizers.rb'
require File.dirname(__FILE__)+'/stackey-stream.rb'

module Hipe
  module Parsie
    class Cfg  # Context-Free Grammar. (Aliased as 'Grammar' below)
               # it's just a table with productions and symbol references.
               # also variously called a 'table' and 'grammar'.
               # experimentally, it is also the parser (but not the parse)

      include No::No, Lingual
      @all = Setesque.new
      class << self
        attr_reader :all
        attr_accessor :ui
        def ui # this is where the buck actually stops
          @ui ||= $stdout
        end
        def clear_tables!
          @all.clear
        end
        def ins
          all.each do |cfg, key|
            if cfg.nil?
              ui.puts "#{key.inspect} : #{cfg.inspect}"
            else
              cfg.ins
            end
          end
        end
      end

      attr_reader :table_name, :productions, :symbols

      def initialize name, &block
        self.class.all.register(name, self)
        $g = self #shh
        @table_name = name
        @symbols = Setesque.new('symbols'){|id| Productions[id]}
        @productions = []
        @current_add_line = 0
        @start_symbol_name = nil
        yield self
      end

      DefaultOpts = {
        :notice_stream => $stdout,
        :verbose?      => nil
      }

      def parse! mixed, opts={}
        opts = HashExtra[DefaultOpts.merge(opts)].methodize_keys!
        process_opts opts

        ctxt = ParseContext.new
        tokenizer = induce_tokenizer mixed
        parse = build_start_parse ctxt

        while ( ! parse.done? ) && ( token = tokenizer.peek )
          ctxt.tic!
          $token = token
          if Debug.verbose?
            Debug.puts "\n\nTOKEN: #{token.inspect} (tic #{ctxt.tic})\n\n\n"
          end
          resp = parse.look token
          if 0 != WANTS & resp
            parse.take! token
            tokenizer.pop!  # do a conditional that runs a hook here
            if ctxt.pushback?
              str = ctxt.pushback_pop.string
              Debug.puts "PUSING BACK: #{str.inspect}" if Debug.verbose?
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

      #
      # for now, it will take anything that looks like a tokenizer,
      # string, or input stream and it might change it to make a tokenzizer
      # out of it. raises parse failure otherwise.
      #
      def induce_tokenizer mixed
        rslt =
        if AbstractTokenizer.looks_like_tokenizer?(mixed)
          mixed
        elsif StringLinesTokenizer.looks_like_string?(mixed)
          StringLinesTokenizer.new(mixed)
        elsif StackeyStream.looks_like_stream?(mixed)
          StackeyStream[mixed]
        else
          fails = [
            StringLinesTokenizer, StackeyStream, AbstractTokenizer
          ].map{|x| x.looks.not_ok_because(mixed) }
          raise ParseFail.new(it_is(mixed.class, oxford_comma(fails)))
        end

        unless AbstractTokenizer.looks_like_tokenizer?(rslt)
          fail(it_is(
            mixed.class, AbstractTokenizer.looks.not_ok_because(rslt)
          ))
        end
        rslt
      end

      def symbol name
        symbols.retrieve name
      end

      # adds a production rule, merging it into
      # or creating a union if necessary
      def add symbol_name, mixed, prod_opts={}, &block
        @current_add_line += 1
        @start_symbol_name = symbol_name if symbols.size == 0
        prod = nil
        begin
          prod = build_production mixed, nil, prod_opts, &block
        rescue ParseParseFail=>e
          return parse_parse_fail e, symbol_name, mixed
        end
        add_prod prod
        prod.table_name = @table_name
        prod.symbol_name = symbol_name
        prod_id = prod.production_id
        if ! symbols.has? symbol_name
          symbols.register symbol_name, prod_id
        else
          symbol_production = self.symbol(symbol_name)
          if symbol_production.kind_of? UnionSymbol
            union_symbol = symbol_production
            union_symbol.add prod
          else
            symbols.remove(symbol_name)
            union = UnionSymbol.new(symbol_production)
            prod_id2 = Productions.register union
            add_prod union
            union.symbol_name = symbol_name
            union.production_id = prod_id2
            union.table_name = @table_name
            union.add prod
            symbols.register(symbol_name, prod_id2)
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

      # default arg just for testing
      #
      def build_start_parse ctxt= ParseContext.new
        base_production = symbol(start_symbol_name)
        # we set the root parse child in a hook so that we can
        # inspect it as soon as possible, before the node builds its children
        parse = base_production.build_parse(ctxt, RootParse) do |p|
          p.after_gets_parse_id do |pp|
            RootParse.only_child = pp
          end
        end
        parse
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

      def build_production mixed, allowed=nil, prod_opts={}, &block
        if allowed
          unless allowed.detect{|x| mixed.kind_of? x }
            raise ParseParseFail.new("can't use #{mixed.class.inspect}"<<
            " here, expecting "<<oxford_comma(allowed.map(&:to_s),' or '))
          end
        end

        prod =
        case mixed
          when Regexp; RegexpProduction.new(mixed,prod_opts)
          when Symbol; SymbolReference.new(mixed)
          when Array;  ConcatProduction.factory(
            self, mixed, prod_opts, &block
          )
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
          next if p.kind_of? UnionSymbol # depends on :note1
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

      def start_symbol_name?
        ! @start_symbol_name.nil?
      end

      def start_symbol_name
        unless @start_symbol_name
          fail("no start symbol (empty grammar?).  "<<
          "use start_symbol_name? to check first")
        end
        @start_symbol_name
      end

      def process_opts opts
        if opts.verbose?
          Debug.verbose = true
          unless opts.notice_stream.nil?
            Debug.out = opts.notice_stream
          end
        end
      end
    end # Cfg
    Grammar = Cfg       # external alias for readability
  end # Parsie
end # Hipe
