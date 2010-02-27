module Hipe

  module Parsie

    module UserFailey
      # something the user did wrong in creating grammars, etc
    end

    class Fail < RuntimeError
      # base class for all exceptions originating from this library
    end

    class AppFail < Fail
      # we did something wrong internally in this library
    end

    class ParseParseFail < Fail
      # something the user did wrong in construting a grammar
      include UserFailey
    end

    class ParseFail < Fail
      # half the reason parsers exist is to do a good job of reporting these
      # then there's this

      include UserFailey # not sure about this

      attr_accessor :parse

      def initialize tokenizer, parse
        @tokenizer = tokenizer
        @parse = parse
      end

      def describe
        ex = @parse.expecting.uniq
        prepositional_phrase = @tokenizer.describe
        "expecting #{ex.join(' or ')} #{prepositional_phrase}"
      end

    end

    No = AppFail # internal shorthand

    class StringLinesTokenizer
      # this might provide a guideline for an interface for tokenizers,
      # e.g. an input stream tokenizer.  note that in lemon the lexer calls
      # the parser

      attr_accessor :has_more_tokens
      def initialize str
        @lines = str.split("\n")
        @offset = -1;
        @last_offset = @lines.length - 1
      end
      def pop
        return nil if @offset > @last_offset
        @offset += 1 # let it get one past last offset
        @lines[@offset]
      end
      def has_more_tokens?
        @offset < @last_offset # b/c pop is the only way to go
      end
      def describe
        if @offset == -1
          "at beginning of input"
        elsif @offset > @last_offset
          if @lines.length == 0
            "and had no input"
          else
            "at end of input near "+@lines[@offset-1].inspect
          end
        else
          "near \""+@lines[@offset]+'"'
        end
      end
    end

    class RegistryList
      include Enumerable # hm
      def initialize; @children = [] end
      def [] idx; @children[idx] end
      def register obj
        @children << obj
        @children.length - 1
      end
      def each &b
        @children.each(&b)
      end
    end

    class Setesque
      class Enumerator
        include Enumerable
        def initialize settie
          @thing = settie
        end
        def each
          @thing.each do |p|
            obj = @thing.retrieve p[0]
            yield [p[0], obj]
          end
        end
      end
      def initialize(name = 'set',&retrieve_block)
        @name = name
        @children = {}
        @retrieve_block = retrieve_block
        if @retrieve_block
          md = /\A(.+)@(.+)\Z/.match(@retrieve_block.to_s)
          me = "#{md[1]}@#{File.basename(md[2])}"
          class << @retrieve_block; self end.send(:define_method,:inspect){me}
        end
      end
      def [] key; @children[key] end
      def retrieve key
        @retrieve_block.call @children[key]
      end
      def objects
        Enumerator.new self
      end
      def has? key; @children.has_key? key end
      def register key, obj
        raise No.new(%{won't redefine "#{key}" grammar}) if
          @children.has_key? key
        @children[key] = obj
        nil
      end
      def replace key, obj
        raise No.new(%{need a key to replace}) unless @children.has_key? key
        old = @children[key]
        @children[key] = obj
        old
      end
      def remove key
        raise No.new("no") unless @children.has_key? key
        @children.delete(key)
      end
      def clear; @children.clear end
      def size; @children.size end
      def keys; @children.keys end

    end

    class ParseContext
      @all = RegistryList.new
      class << self
        attr_reader :all
      end

      def token_frame_production_parsers
        @token_locks[:token_frame_production_parsers]
      end

      def visiting name
        case name
        when :look  :     @token_locks[:look]
        when :ok? :       @token_locks[:ok?]
        when :done? :     @token_locks[:done?]
        when :expecting : @token_locks[:expecting]
        end
      end

      alias_method :tfpp, :token_frame_production_parsers
      attr_reader :context_id
      def initialize
        @context_id = self.class.all.register(self)
        @token_locks = Hash.new do |h,k|
          h[k] = Setesque.new(k)
        end
        $tf = @token_frame
      end
      def new_token
        @token_locks.each{|p| p[1].clear }
      end
    end

    class Cfg; end      # context-free grammar, also called a 'table' here
    Grammar = Cfg       # external alias for readability

    class Cfg
      class Productions < RegistryList; end
      class Symbols     < Setesque;  end

      @all = Setesque.new
      class << self
        attr_reader :all
        def clear_tables!; @all.clear end
      end

      attr_reader :table_name
      attr_reader :symbols # just for concat to check its references

      def initialize name, &block
        self.class.all.register(name, self)
        $g = self #shh
        @table_name        = name
        p = @productions = Productions.new
        @symbols = Symbols.new('symbols'){|id| p[id]}
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
        prod.table_name = @table_name
        prod.symbol_name = symbol_name
        prod_id = @productions.register prod
        prod.production_id = prod_id
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
            prod_id2 = @productions.register union
            union.symbol_name = symbol_name
            union.production_id = prod_id2
            union.table_name = @table_name
            union.add prod
            @symbols.register(symbol_name, prod_id2)
          end
        end
        nil
      end

      def parse! mixed
        ctxt = ParseContext.new
        tokenizer = build_tokenizer mixed
        parse = symbol(@start_symbol_name).spawn(ctxt)
        while token = tokenizer.pop
          ctxt.new_token
          parse.look token
          # @todo push back on the stack for partial matches
          break if parse.done?
        end
        if ! parse.ok?
          @parse_fail = ParseFail.new(tokenizer, parse)
          nil
        elsif tokenizer.has_more_tokens?
          @parse_fail = ParseFail.new(tokenizer, parse)
          nil
        else
          parse
        end
      end

      def reference_check
        missing = []
        @productions.each do |prod|
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
            raise ParseParseFail.new("can't use #{x.class.inspect} here")
          end
        end
        case mixed
          when Regexp: RegexpProduction.new(mixed)
          when Symbol: SymbolReference.new(mixed)
          when Array:  ConcatProduction.new(self, mixed)
          when String: StringProduction.new(mixed)
          else raise ParseParseFail.new("no: #{mixed.inspect}")
        end
      end

      def parse_fail
        @parse_fail
      end

      def build_tokenizer mixed
        case mixed
        when String: StringLinesTokenizer.new(mixed)
        else raise ParseParseFail.new("no: #{mixed.inspect}")
        end
      end

      # this isn't formal,
      def to_bnf opts={}
        show_pids = opts[:pids]
        prerendered = []
        left_max = 0
        fail = @productions.detect{|x| ! x.symbol_name.kind_of? Symbol }
        if fail
          sym_name = fail.symbol_name
          raise ParseParseFail("Must have only symbol names for "<<
          "productions, not #{fail.inspect}")
        end
        @productions.each do |p|
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


    # *************** Production & Parse Mixins ***********************

    module Productive
      def symbol_name= name;
        Productive.make_getter(self,:symbol_name,name)
      end
      def production_id= production_id
        Productive.make_getter(self,:production_id,production_id)
      end
      def table_name= foo
        Productive.make_getter(self,:table_name,foo)
      end
      def self.make_getter(obj,meth,val)
        if obj.respond_to? meth
          raise No.new('no')
        end
        class<<obj; self end.send(:define_method,meth){val}
      end
    end

    module ParseStatusey
      def done?
        raise AppFail.new('no') if @done.nil?
        @done
      end
      def ok?
        raise AppFail.new('no') if @ok.nil?
        @ok
      end
    end

    module Inspecty
      def class_basename
        self.class.to_s.split('::').last
      end
      def insp; $stdout.puts inspct end
      def inspct_tiny
        sprintf("<%s%s#%s>",
          class_basename.scan(/[A-Z]/).join(''),
          @symbol_name.inspect,
          @parse_id
        )
      end
    end

    module Misc
      def bool? mixed
        [TrueClass,FalseClass].include? mixed.class
      end
    end

    module SymbolAggregatey
      def _spawn ctxt, claz
        if ctxt.tfpp.has? production_id
          ParseReference.new ctxt, production_id
        else
          p = claz.new(self, ctxt) # note2
          ctxt.tfpp.register(production_id, p)
          p.resolve_children
          p
        end
      end
    end

    module AggregateParsey
      def _resolve_children symbol, ctxt
        @children = symbol.children.map do |sym|
          sym.spawn(ctxt)
        end
      end
    end

    def inspct_extra(ll,ctx,opts)
    end

    module AggregateParseInspecty
      include Inspecty
      def inspct_extra ll, ctx, opts
      end
      def inspct ctx=InspectContext.new, opts={}
        if ctx.visiting.has? parse_id
          opts[:word] = true
        else
          ctx.visiting.register parse_id, nil
        end
        my_ind = ctx.indent.dup
        ctx.increment_indent
        ll = []
        ll << sprintf('#<%s:%s',class_basename,@parse_id.inspect)
        ll << sprintf("@symbol_name=%s",@symbol_name.inspect)
        ll << sprintf("@done=%s",@done.inspect)
        ll << sprintf("@ok=%s",@ok.inspect)
        inspct_extra(ll,ctx,opts)
        if opts[:word]
          ll << "@children(#{@children.size})"
          return (ll*', '+' >')
        end
        l = []
        l << (ll*",\n #{my_ind}")

        last = @children.length - 1
        l << " #{my_ind}@children(#{@children.size})="
        @children.each_with_index do |c,i|
          if (i==0)
            s = ("  #{my_ind}["<<c.inspct(ctx))
          else
            s = ("   #{my_ind}"<<c.inspct(ctx))
          end
          s << ']' if i==last
          l << s
        end
        l.last << '>'
        l * "\n"
      end
    end

    module LookieLocky
      def look_lock
        sett = parse_context.visiting(:look)
        if sett.has? parse_id
          throw :look_is_wip,  {:pid=>parse_id}
        else
          sett.register(parse_id, :look_wipping)
        end
        nil
      end

      def look_unlock
        sett = parse_context.visiting(:look)
        rm = sett.remove(parse_id)
        raise No.new("unexpected value") unless :look_wipping == rm
        nil
      end

      def parse_context
        ParseContext.all[@context_id]
      end
    end

    class StringProduction
      include Productive
      def initialize string
        raise ParseParseFail("no").new if
          (""==string || !string.kind_of?(String))
        @string = string
        @done = false
        @ok = false
      end
      def spawn ctxt
        StringParse.new(@string)
      end
      def to_bnf_rhs; @string.inspect end
    end

    class RegexpProduction
      include Productive
      attr_accessor :re
      def initialize re; @re = re end
      def spawn ctxt
        RegexpParse.new(@re, symbol_name)
      end
      # @todo not bnf!
      def to_bnf_rhs;
        @re.inspect
      end
    end

    class StringParse
      include ParseStatusey
      def initialize string
        @string = string
        @done = false
        @ok = false
      end
      def look token
        raise No.new("too many looks") if @done
        @done = true
        if (token==@string)
          @ok = true
        end
      end
      def expecting
        (@ok && @done) ? ['no more input'] : [@string.inspect]
      end
      def tree; self end
      def inspct _,o=nil;
        inspect
      end
    end

    class RegexpParse
      include ParseStatusey, Inspecty
      attr_accessor :matches, :name
      def initialize(re, name)
        @re = re
        @name = name
        @done = false
        @ok = false
        @md = nil
      end
      def expecting
        (@ok && @done) ? ['no more input'] : [@name]
      end
      def look str
        raise No.new("too many looks") if @done
        @done = true
        md = @re.match(str)
        @md = md ? md : false
        @ok = !! md
      end
      def tree; self end
      def inspct _,o=nil;
        inspect
      end
    end

    class SymbolReference
      include Productive
      def target; @target end
      def initialize symbol
        @target = symbol
      end
      def reference_check
        unless Cfg.all[table_name].symbols.has?(@target)
          throw :ref_fail, {:name=>@target}
        end
      end
      def spawn ctxt
        symbol_production = Cfg.all[table_name].symbol(@target)
        symbol_production.spawn ctxt
      end
      def to_bnf_rhs; @target.to_s end
    end

    class ParsesRegistry < RegistryList; end

    Parses = ParsesRegistry.new

    class ParseReference
      include Misc
      # this uses the variable name sett instead of set only b/c 'set'
      # is a command in ruby debug
      include Inspecty
      class<<self
        attr_accessor :all
      end
      @all = RegistryList.new
      def initialize ctxt, production_id
        p = ctxt.tfpp[production_id]
        @ref_id = self.class.all.register(self)
        @p = p
        @ctxt_id = ctxt.context_id
      end
      def context
        ParseContext.all[@ctxt_id]
      end
      def inspct ctx=InspectContext.new, o=nil
        sprintf("#<%s:#%s:%s>",class_basename,@ref_id, @p.inspct(ctx))
      end
      def look token
        # we let the implementors manage locking
        @p.look token
      end
      def ok?
        pid = @p.parse_id
        sett = context.visiting(:ok?)
        if sett.has? pid
          throw :ok_is_wip,  {:pid=>pid}
        else
          sett.register(pid, :ok_wipping)
          rslt = @p.ok? # might be nil!?
          unless bool? rslt
            raise No.new("need bool has #{rslt.inspect} for pid #{pid}")
          end
          r2 = sett.remove(pid)
          raise No.new('no wipping') unless :ok_wipping == r2
          rslt
        end
      end
      def done?
        pid = @p.parse_id
        sett = context.visiting(:done?)
        if sett.has? pid
          val = sett[pid]
          if val == :done_wipping
            throw :done_is_wip
          else
            raise No.new("for now this is the only way")
          end
        else
          sett.register pid, :done_wipping
          hard_to_get = @p.done?
          dip = sett.remove(pid)
          if ! (:done_wipping == dip)
            debugger; "whip no"
            raise No.new('no - dip')
          else
            rslt = hard_to_get
          end
        end
        rslt
      end

      def expecting
        set = context.visiting(:expecting)
        if set.has? @p.parse_id
          [] # not sure about this
        else
          set.register @p.parse_id, nil
          rslt = @p.expecting # might be nil!?
          # not sure about this
          rslt
        end
      end
    end

    class UnionSymbol
      include Productive, SymbolAggregatey
      attr_accessor :children
      def initialize sym
        @children = [sym]
      end
      def add child
        raise No.new("children of a union must "<<
        "have the same name: #{symbol_name.inspect}, "<<
        "#{child.symbol_name.inspect}") unless
          symbol_name == child.symbol_name
        @children.push child
        nil
      end
      def spawn ctxt
        _spawn ctxt, UnionParse
      end
      # doesn't need reference_check as long as note1
    end

    class InspectContext
      attr_reader :indent, :visiting
      def initialize
        @indent = ''
        @visiting = Setesque.new('nodes rendering')
      end
      def increment_indent
        @indent << '  '
      end
    end

    class UnionParse
      include AggregateParsey, AggregateParseInspecty, LookieLocky
      attr_reader :parse_id # make sure this is set in constructor
      def initialize union, ctxt # note2 - this is only called in one place
        @symbol_name = union.symbol_name
        @production_id = union.production_id
        @parse_id = Parses.register self
        @context_id = ctxt.context_id
        @union_symbol = union
        @ctxt = ctxt
        @done = nil
        @ok = nil
        @have_looked = false
      end
      def resolve_children
        _resolve_children @union_symbol, @ctxt
        remove_instance_variable '@union_symbol'
        remove_instance_variable '@ctxt'
        # in the running is an *ordered* list of ids (ordered by precedence)
        @in_the_running = (0..@children.length-1).map
      end
      def expecting
        m = []
        @children.each_with_index do |c,i|
          m.concat c.expecting
        end
        m
      end
      def look token
        # always set done and ok here or change their methods
        raise No.new("won't look when done") if @done
        look_lock
        @done = nil
        @prev_ok = @ok
        @ok = nil
        idx_ok   = []
        idx_done = []
        @in_the_running.each do |idx|
          child = @children[idx]
          looking = catch(:look_is_wip) do
            child.look(token)
            nil
          end
          if looking
            if looking[:pid] != @parse_id
              raise No.new("big problems - caught the wrong look wip")
            else
              # we just skip recusive looks !?
              # puts "skipping recursive look for #{inspct_tiny}"
              # the node that invokes us, self, is that forever
              # out of the running !??
              # we are forever out of the running if we are looking !?? @todo
              idx_done << idx
              next
            end
          end
          c_ok   = child.ok?
          c_done = child.done?
          idx_ok   << idx if c_ok
          idx_done << idx if c_done
        end
        done_and_ok_this_round = idx_done & idx_ok
        @in_the_running -= idx_done
        @done = @in_the_running.size == 0
        @ok   = idx_ok.size > 0
        if (@prev_ok && !@ok)
          debugger; 'life of suck'
        end
        @have_looked = true
        look_unlock
        nil
      end

      def ok?
        # you are ok if one of your children is ok
        return @ok unless @ok.nil?
        if @have_looked
          raise No.new('why is ok not set if we have looked?')
        end
        @ok = !! @children.detect{|x| x.ok? }
      end

      def done?
        # you are done iff all of your children are done
        return @done unless @done.nil?
        if @have_looked
          raise No.new('why is done not set if we have looked?')
        end
        @done = ! @children.detect{|c| ! c.done?}
      end

      def tree
        # @todo ambiguities
        winner = @children.detect{|x| x.done? && x.ok? }
        winner ? winner.tree : nil
      end

      def inspct_extra(ll,ctx,opts)
        ll << sprintf("@in_the_running=%s",@in_the_running.inspect)
      end
    end

    class ConcatProduction
      include Productive, SymbolAggregatey
      attr_accessor :children
      def initialize grammar, ary
        @children = ary.map do |x|
          p = grammar.build_production(x,[String, Symbol])
          p.table_name = grammar.table_name
          # as they are only strings or symbol references, they don't
          # need to register with the table and get production ids, etc
          p
        end
      end
      def spawn ctxt
        _spawn ctxt, ConcatParse
      end
      def reference_check
        missing = []
        @children.select{|p| p.kind_of? SymbolReference}.each do |p|
          if (fail = catch(:ref_fail){ p.reference_check; nil })
            missing << fail[:name]
          end
        end
        throw :ref_fail, {:names => missing } if missing.length > 0
      end
      def to_bnf_rhs; @children.map(&:to_bnf_rhs) * ' ' end
    end

    class ConcatParse
      include AggregateParsey, AggregateParseInspecty, LookieLocky
      attr_reader :parse_id # make sure this is set in constructor
      attr_accessor :children
      def initialize(symbol, ctxt)
        @table_name = symbol.table_name
        @symbol_name = symbol.symbol_name
        @production_id = symbol.production_id
        @parse_id = Parses.register self
        @context_id = ctxt.context_id
        @offset = 0
        @concat_symbol = symbol
        @ctxt = ctxt
        @done = nil
        @ok = nil
        @done_not_ok = nil
      end

      def resolve_children
        _resolve_children @concat_symbol, @ctxt
        remove_instance_variable '@concat_symbol'
        remove_instance_variable '@ctxt'
        @ok_index   = @children.length - 1 # @todo trailing zero
        @done_index = @children.length - 1
      end

      def look token
        raise No.new("concat won't look when done") if @done
        look_lock
        @done = nil
        @ok = nil
        curr = @children[@offset]
        @prev_ok = curr.ok?
        if curr.done?
          raise No.new("child should never be done here")
        end
        curr.look token
        if curr.done?
          curr.ok? ? advance_done_and_ok : advance_done_and_not_ok(token)
        else
          curr.ok? ? advance_not_done_and_ok : advance_not_done_and_not_ok
        end
        look_unlock
      end

      def advance_done_and_ok # our favorite state
        if @offset < @done_index
          @offset += 1
        end
        @ok   = @offset >= @ok_index
        @done = @offset >= @done_index
      end

      def advance_done_and_not_ok(token) # note3
        if @prev_ok
          debugger; "implement child is not ok,
            was ok before, need to look again"
        else
          # leave offset alone for now per note3
          @done = true
          @ok = false
        end
      end

      def advance_not_done_and_ok
        # stay here, we will use note3 algorithm
        @ok   = @offset >= @ok_index
        @done = @offset >= @done_index
      end

      def advance_not_done_and_not_ok
        if @prev_ok
          debugger; "i hate this one - probably advance"
        end
        @done = false
        @ok   = @offset >= @ok_index
      end

      def ok?
        return @ok unless @ok.nil?
        @ok = @offset >= @ok_index
      end

      def done?
        # todo this returns lies at the beginning note4 (see test)
        return @done unless @done.nil?
        @done = @offset >= @done_index
      end

      def expecting
        rs = @children[@offset].expecting
        rs
      end
    end
  end
end
# note1 - UnionSymbols are only ever created by the table, pipe operator not
#  supported
# note2 - see above
# note3- this is our 'look again' algorithm
