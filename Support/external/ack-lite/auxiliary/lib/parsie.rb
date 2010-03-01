root = File.dirname(__FILE__)
require root+'/mixins.rb'
require root+'/support.rb'

module Hipe

  module Parsie

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
        when :look       ; @token_locks[:look]
        when :ok?        ; @token_locks[:ok?]
        when :done?      ; @token_locks[:done?]
        when :expecting  ; @token_locks[:expecting]
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
      def tic
        @token_locks.each{|p| p[1].clear }
      end
    end


    class ParsesRegistry      < RegistryList; end
    class ProductionsRegistry < RegistryList; end

    Parses = ParsesRegistry.new
    Productions = ProductionsRegistry.new
    $p = Parses # shh
    $pr = Productions


    class Cfg     # context-free grammar, also called a 'table' here
      include NaySayer
      @all = Setesque.new
      class << self
        attr_reader :all
        def clear_tables!; @all.clear end
      end

      attr_reader :table_name, :productions, :symbols

      def initialize name, &block
        self.class.all.register(name, self)
        $g = self #shh
        @table_name        = name
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

      def parse! mixed
        ctxt = ParseContext.new
        tokenizer = build_tokenizer mixed
        parse = symbol(@start_symbol_name).spawn(ctxt)
        while token = tokenizer.pop
          ctxt.tic
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
            raise ParseParseFail.new("can't use #{x.class.inspect} here")
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

      def parse_fail;
        @parse_fail
      end

      def build_tokenizer mixed
        case mixed
        when String; StringLinesTokenizer.new(mixed)
        else raise ParseParseFail.new("no: #{mixed.inspect}")
        end
      end

      # this isn't formal,
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

    class StringProduction
      include Productive
      attr_accessor :string_literal
      def initialize string
        raise ParseParseFail("no").new if
          (""==string || !string.kind_of?(String))
        @string_literal = string
        @done = false
        @ok = false
      end
      def spawn ctxt
        StringParse.new(self)
      end
      def to_bnf_rhs; @string_literal.inspect end
    end

    class RegexpProduction
      include Productive
      attr_accessor :re
      def initialize re; @re = re end
      def spawn ctxt
        RegexpParse.new(self)
      end
      # @todo not bnf!
      def to_bnf_rhs;
        @re.inspect
      end
    end

    class StringParse
      include ParseStatusey, Terminesque, NaySayer
      def initialize prod
        @string = prod.string_literal
        @production_id = prod.production_id
        @done = false
        @ok = false
      end
      def look token
        no("too many looks") if @done
        @done = true
        if (token==@string)
          @ok = true
        end
      end
      def expecting
        (@ok && @done) ? ['no more input'] : [@string.inspect]
      end
      def inspct _,o=nil;
        inspect
      end
      def tree
        return @value_tree unless @value_tree.nil?
        @value_tree =
          if (@done&&@ok)
            ParseTree.new(:string, nil, @production_id, @string)
          else
            false
          end
        @value_tree
      end
    end

    class RegexpParse
      include ParseStatusey, Inspecty, Terminesque, NaySayer
      attr_accessor :matches, :name
      def initialize production
        @re = production.re
        @production_id = production.production_id
        @name = production.symbol_name
        @done = false
        @ok = false
        @md = nil
      end
      def expecting
        (@ok && @done) ? ['no more input'] : [@name]
      end
      def look str
        no("too many looks") if @done
        @done = true
        md = @re.match(str)
        @md = md ? md : false
        @ok = !! md
      end
      def inspct _,o=nil;
        inspect
      end
      def tree
        return @tree unless @tree.nil?
        @tree = begin
          if ! @md then false
          else
            val = @md.captures.length > 0 ? @md.captures : @md[0]
            ParseTree.new(:regexp, @name, @production_id, val)
          end
        end
        @tree
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

    class ParseReference
      include Misc, NaySayer
      # this uses the variable name sett instead of set only b/c 'set'
      # is a command in ruby debug
      include Inspecty
      @all = RegistryList.new
      class<<self
        attr_accessor :all
      end
      def initialize parse
        @ref_id = self.class.all.register(self)
        @context_id = parse.parse_context.context_id
        @parse_id = parse.parse_id
      end
      def hypothetical?; false end
      def target; Parses[@parse_id] end
      def parse_context; ParseContext.all[@context_id] end
      def inspct ctx=InspectContext.new, o={}
        sprintf("#<%s:#%s:%s>",class_basename,@ref_id, target.inspct(ctx,o))
      end
      def look token
        # we let the implementors manage locking
        target.look token
      end
      def ok?
        pid = @parse_id
        sett = parse_context.visiting(:ok?)
        if sett.has? pid
          throw :ok_wip,  {:pid=>pid}
        else
          sett.register(pid, :ok_wipping)
          rslt = target.ok? # might be nil!?
          unless bool? rslt
            no("need bool has #{rslt.inspect} for pid #{pid}")
          end
          r2 = sett.remove(pid)
          no('no wipping') unless :ok_wipping == r2
          rslt
        end
      end
      def done?
        pid = @parse_id
        sett = parse_context.visiting(:done?)
        if sett.has? pid
          val = sett[pid]
          if val == :done_wipping
            throw :done_wip
          else
            no("for now this is the only way")
          end
        else
          sett.register pid, :done_wipping
          hard_to_get = target.done?
          dip = sett.remove(pid)
          if ! (:done_wipping == dip)
            no("no - dip")
          else
            rslt = hard_to_get
          end
        end
        rslt
      end

      def expecting
        set = parse_context.visiting(:expecting)
        if set.has? @parse_id
          [] # not sure about this
        else
          set.register @parse_id, nil
          rslt = target.expecting # might be nil!?
          # not sure about this
          rslt
        end
      end
    end

    class UnionSymbol
      include Productive, SymbolAggregatey
      attr_accessor :children
      def initialize sym
        @children = AryExt[[sym]]
      end
      def add child
        no("children of a union must "<<
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

    NotHypothetical = :is_not
    IsHypothetical = :is
    NoChildren     = :no

    class UnionParse
      include AggregateParsey, AggregateParseInspecty, LookieLocky, NaySayer
      attr_reader :parse_id # make sure this is set in constructor
      attr_reader :children # debuggin
      def initialize union, ctxt # note2 - this is only called in one place
        @production_id = union.production_id
        @context_id = ctxt.context_id
        @parse_id = Parses.register self
        @done = nil
        @ok = nil
        @have_looked = false
        @hypothetical = NotHypothetical
      end
      def hypothetical?
        @hypothetical == IsHypothetical
      end
      def kidnapping_notify(idxs);
        no = @in_the_running & idxs
        no("don't kidnap a child that is in the running (?)") if no.size > 0
        nil
      end
      def kidnapped_notify(idxs,thing)
        idxs.reverse.each do |idx|
          @children.delete_at(idx)
          # @children[idx] = {:kidnapped_to => thing.new_parent_id }
        end
      end
      def resolve_children
        _resolve_children
        # in the running is an *ordered* list of ids (ordered by precedence)
        # that are not done (still accepting). doesn't matter if they are ok
        @in_the_running = (0..@children.length-1).map
      end
      def expecting
        m = []
        @children.each_with_index do |c,i|
          m.concat c.expecting
        end
        m
      end

      def spawn_hypothetical caller
        spwn = UnionParse.new(production, parse_context)
        spwn.extend Hypothetic
        spwn.init_hypothetic self, caller
        spwn
      end

      def look token # always set done and ok here or change their methods
        no("won't look when done") if @done
        look_lock
        @done = nil; @prev_ok = @ok;  @ok = nil
        idx_ok   = []; idx_done = []; skipped = []
        @in_the_running.each do |idx|
          child = @children[idx]
          wip = catch(:look_wip){ child.look(token); nil }
          if ! wip
            idx_ok   << idx if child.ok?
            idx_done << idx if child.done?
          elsif wip[:pid] != @parse_id
            throw :look_wip, wip
          else
            puts "#{inspct_tiny} skipping over #{token}" # see note5 ?
            skipped << idx # still in the running
          end
        end
        look_unlock
        @have_looked = true
        @ok   = idx_ok.size > 0
        @in_the_running -= idx_done
        @done = @in_the_running.size == 0
        resolve_skipped(skipped) if skipped.length > 0
        if (@prev_ok && !@ok)
          puts("#{inspct_tiny} was ok before, not ok after looking at "<<
          "#{token}")
          # no("more fun for you here")
        end
        nil
      end

      def resolve_skipped skipped
        oks = []
        dones = []
        skipped.each do |idx|
          child = @children[idx]
          child.re_evaluate!
          oks   << idx if child.ok?
          dones << idx if child.done?
        end
        @in_the_running -= dones
        if @ok == false
          @ok = oks.size > 0
        end
      end

      def winners; @children.select{|x| x.done? && x.ok? } end

      def ok?
        # you are ok if one of your children is ok
        return @ok unless @ok.nil?
        if @have_looked
          no('why is ok not set if we have looked?')
        end
        @ok = !! @children.detect{|x| x.ok? }
      end

      def done?
        # you are done iff all of your children are done
        return @done unless @done.nil?
        if @have_looked
          raise no('why is done not set if we have looked?')
        end
        @done = ! @children.detect{|c| ! c.done?}
      end

      def tree
        @tree ||= begin
          winners = self.winners
          if winners.size > 1
            winner = disambiguate_or_raise winners
            tree_from_winner winner
          elsif winners.size == 0
            false # or throw error?
          else
            tree_from_winner winners[0]
          end
        end
      end

      def tree_from_winner winner
        my_val = winner.tree
        ParseTree.new(:union, symbol_name, @production_id, my_val)
      end

      def disambiguate_or_raise winners
        one = winners.detect{|x| ! x.kind_of? Terminesque }
        if one
          $t = self
          no(
          "ambiguous parse tree - more than one winner and they aren't all"<<
          " terminal. Tree set to $t.")
        end
        winners.shift
      end

      def inspct_extra(ll,ctx,opts)
        inspct_attr(ll,'@in_the_running')
        inspct_attr(ll, '@hypothetical'){|v| v!= NotHypothetical}
      end

      def prune_references!
        remove = @children.each_with_index.select do |child,idx|
          child.kind_of? ParseReference
        end.map{|foo| foo[1]}
        @in_the_running -= remove
        removed = []
        remove.reverse.each do |idx|
          removed << @children.delete_at(idx)
        end
        @ok = @children.map{|c| c.ok?}.size > 0
        @done = @in_the_running.size == 0
        removed
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
        AryExt[@children]
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
      include AggregateParsey, AggregateParseInspecty, LookieLocky, NaySayer
      attr_reader :parse_id # make sure this is set in constructor
      attr_accessor :children
      def initialize(symbol, ctxt)
        @production_id = symbol.production_id
        @context_id = ctxt.context_id
        @parse_id = Parses.register self
        @offset = 0
        @done = nil
        @ok = nil
        @last_token_seen = :none
        @evaluate_tic = 0 # temp debugging stuff
        @last_evaluate = nil
      end

      def inspct_extra(ll,ctx,opts)
        inspct_attr(ll,%w(@last_token_seen @offset))
      end

      def resolve_children
        _resolve_children
        # *after* it processes the child at that index, it will be ..
        @ok_index   = @children.length - 1 # @todo trailing zero
        @final_index = @children.length - 1
      end

      def look token
        no("concat won't look when done") if @done
        look_lock
        @last_token_seen = token
        # before we change our state ..
        @children.select{|c| c.hypothetical?}.map(&:kidnap!)
        @done = nil
        @ok = nil
        curr = @children[@offset] # might be a union that references self
        no("child should never be done here") if curr.done?
        child_prev_ok = curr.ok?
        @evaluate_tic += 1
        wip = catch(:look_wip) do
          curr.look token # this can throw from a recursive child or another
          nil
        end
        if ! wip
          @child_prev_ok = child_prev_ok
          re_evaluate!
        elsif wip[:pid] != @parse_id
          throw :look_wip, wip
        else # we skip over the recursive child if it was ok and
          # look with the next child and evaluate there
          advance_over_recursive_child!
          curr = @children[@offset]
          @child_prev_ok = curr.ok?
          curr.look token
          re_evaluate!
        end
        look_unlock
      end

      def advance_over_recursive_child!
        curr = @children[@offset]
        no("not going to advance over recusive child unless "<<
        "it is ok") unless curr.ok?
        no("haven't dealt with current being done before") if curr.done?
        no("have never dealt with when recursive child is final element") if
          @offset == @final_index
        was_done = curr.done?
        refs = curr.prune_references! # @todo i think we want these?
        if ! was_done
          # ...
        end
        @offset += 1
        nil
      end

      def re_evaluate!
        no("tried to evaluate twice on the same token!") if
          (@last_evaluate==@evaluate_tic)
        @last_evaluate = @evaluate_tic
        curr = @children[@offset]
        if curr.done?
          curr.ok? ? advance_done_and_ok : advance_done_and_not_ok
        else
          curr.ok? ? advance_not_done_and_ok : advance_not_done_and_not_ok
        end
      end

      def advance_done_and_ok # our favorite state
        # the child we just evaluated was done and ok,
        # we move forward or we are finished!
        @ok   = @offset >= @ok_index
        @done = @offset >= @final_index
        if @offset < @final_index
          @offset += 1
        end
        nil
      end

      def advance_done_and_not_ok # note3
        if @child_prev_ok
          no("implement child is not ok,
            was ok before, need to look again")
        else
          # leave offset alone for now per note3
          @done = true
          @ok = false
        end
      end

      def advance_not_done_and_ok
        # stay here, we will use note3 algorithm
        @ok   = @offset >= @ok_index
        @done = @offset >= @final_index
        curr = @children[@offset]
        # uh, we want to insulate its state change
        # when it gets a next token
        if curr.kind_of? ParseReference
          nu = curr.target.spawn_hypothetical self
          @children[@offset] = nu
        end
      end

      def advance_not_done_and_not_ok
        # always stay
        @done = false
        @ok   = @offset >= @ok_index
      end

      def ok?
        return @ok unless @ok.nil?
        @offset >= @ok_index
      end

      def done?
        # todo this returns lies at the beginning note4 (see test)
        return @done unless @done.nil?
        @offset >= @final_index
      end

      def expecting
        rs = @children[@offset].expecting
        rs
      end

      def tree
        childs = @children.map(&:tree)
        ParseTree.new(:concat, symbol_name, @production_id, childs)
      end
    end

    class ParseTree < Struct.new(
      :type, :symbol_name, :production_id, :value
    )
      def inspct ctx=InspectContext.new,opts={};
        l = []
        ind = ctx.indent.dup
        ctx.indent_indent!
        l << sprintf(
          "#<ParseTree tp:%s nm:%s prod:%s chldrn:",
          type,symbol_name,production_id
        )
        if value.kind_of? ParseTree
          l << value.inspct(ctx,opts)
        else
          l << value.inspect
        end
        l.last << ">"
        s = l.join(" ")
        if s.length < 80
          return s
        else
          return l * "\n   #{ind}"
        end
      end
    end
  end
end
# note1 - UnionSymbols are only ever created by the table, pipe operator not
#  supported
# note2 - that is only called in one place
# note3 - this is our 'look again' algorithm
# note5 - @todo: we just skip recusive looks !?
#   the node that invokes us, self, is that forever
#   out of the running !??
#   we are forever out of the running if we are looking !??
# note6 - the whole re-evaluate thing might be better served by code blocks?
# note7 - tfpp is ridiculous - its a way to avoid recursion
