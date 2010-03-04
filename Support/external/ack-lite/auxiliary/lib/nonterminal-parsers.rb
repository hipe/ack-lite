require File.dirname(__FILE__) + '/nonterminal-inspecty.rb'

module Hipe
  module Parsie

    # for parsers - nonterminals

    module NonterminalParsey
      include Misc
      def production
        Productions[@production_id]
      end
      def parse_context
        ParseContext.all[@context_id]
      end
      def symbol_name
        production.symbol_name
      end
      def locks_init
        @lock = {
          :ok?   => false,
          :done? => false,
          :look  => false,
          :take! => false
        }
      end
      def looking?; @lock[:look] end
      def doneing?; @lock[:done?] end
      def oking?;   @lock[:ok?] end
      def look_lockout &block
        no("can't look when done") if done?
        common_lockout :look, &block
      end
      def take_lockout &block
        no("can't take when done") if done?
        common_lockout :take!, &block
      end
      def done_lockout &block
        common_lockout :done?, &block
      end
      def ok_lockout &block
        common_lockout :ok?, &block
      end
      def common_lockout type, &block
        wip_name = "wip_#{type}".to_sym # :wip_ok? :wip_done? :wip_look
        throw wip_name, {:pid=>parse_id} if @lock[type]
        @lock[type] = true
        wip = catch(wip_name) do
          yield # this may throw from self as child, depending on how we
          # choose to implement this.  In the client code (i.e. anywhwere
          # other than here) client should catch wips originating
          # from self (or target) and take appropriate measures.  Here we
          # catch all wips and rethrow them to bubble them up.  If we catch a
          # wip that originated (by necessity) somewhere below us but did not
          # originate from us, we unlock our own lock first so we are not
          # locked out later
          nil
        end
        if wip
          @lock[type] = false if (wip && wip[:pid]!=parse_id)
          throw wip
        end
        @lock[type] = false
        nil
      end
    end

    class UnionParse
      include NonterminalParsey, NonterminalInspecty, FaileyMcFailerson,
        StrictOkAndDone
      attr_reader :parse_id # make sure this is set in constructor
      attr_reader :children # debuggin
      def initialize union, ctxt # note2 - this is only called in one place
        locks_init
        @production_id = union.production_id
        @context_id = ctxt.context_id
        @parse_id = Parses.register self
        @done = nil; @ok = nil
        # in the running is an *ordered* list of ids (ordered by precedence)
        # that are not done (still accepting). doesn't matter if they are ok
        @in_the_running = false
      end
      def build_children!
        context = parse_context
        @children = production.children.map do |sym|
          sym.build_parse context
        end
        AryExt[@children]
        @in_the_running = (0..@children.length-1).map
        evaluate!
      end
      def evaluate!
        idxs_done = []
        done_lockout do
          @in_the_running.each do |idx|
            child = @children[idx]
            idxs_done << idx if child.done?
          end
        end
        ok_idx = nil
        ok_lockout do
          ok_idx = @in_the_running.detect{|idx| @children[idx].ok?}
        end
        @in_the_running -= idxs_done
        @done = @in_the_running.size == 0
        @ok = ! ok_idx.nil?
        nil
      end
      # @todo the below should take into account in the running!
      def expecting
        m = []
        @children.each_with_index do |c,i|
          m.concat c.expecting
        end
        m
      end
      def look token
        puts "#{inspct_tiny} sees token \"#{token}\"" if Debug.true?
        idxs_open = []
        idxs_ok   = []
        idxs_want = []
        look_lockout do
          @in_the_running.each do |idx|
            child = @children[idx]
            child_resp = child.look token
            idxs_want << idx if (0 != WANTS & child_resp)
            idxs_ok   << idx if (0 != SATISFIED & child_resp)
            idxs_open << idx if (0 != OPEN & child_resp)
          end
        end
        ok_bit = idxs_ok.size > 0 ? SATISFIED : 0
        open_bit = idxs_open.size > 0 ? OPEN : 0
        want_bit = idxs_want.size > 0 ? WANTS : 0
        ok_bit | open_bit | want_bit
      end
      # see note8 ambiguity
      def take! token
        idxs_want = []
        @in_the_running.each do |idx|
          child = @children[idx]
          resp = child.look token
          idxs_want << idx if (0 != WANTS & resp)
        end
        no("can't take what i don't want") if (0==idxs_want.size)
        take_lockout do
          idxs_want.each do |idx|
            @children[idx].take! token
          end
        end
        evaluate!
      end
      def winners; @children.select{|x| x.done? && x.ok? } end
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
      # unlike concat trees, a union tree selects its one winner and uses the
      # tree of that winning child to represent its tree
      def tree_from_winner winner
        winner.tree
        # my_val = winner.tree
        # ParseTree.new(:union, symbol_name, @production_id, my_val)
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
    end


    class ConcatParse
      include NonterminalParsey, NonterminalInspecty, StrictOkAndDone
      attr_reader :parse_id # make sure this is set in constructor
      attr_accessor :children, :final_offset, :satisfied_offset

      def initialize production, ctxt
        @production_id = production.production_id
        @context_id = ctxt.context_id
        @parse_id = Parses.register self
        @offset = -1 # 3 offsets below must always be a valid index or -1
        @final_offset = production.final_offset
        @satisfied_offset = production.satisfied_offset
        @done = nil
        @ok = nil
      end

      def build_children!
        prod_childs = production.children
        ctxt = parse_context
        @children = AryExt[Array.new(prod_childs.size)]
        (@offset+1..@final_offset).each do |idx|
          @children[idx] = prod_childs[idx].build_parse ctxt
          break unless prod_childs[idx].zero_width?
        end
        evaluate!
        nil
      end

      def evaluate!
        @ok = @offset == @satisfied_offset
        @done = @offset == @final_offset
      end

      def tree
        no("no asking for tree if not ok") unless @ok
        return @tree if (@done && @tree)
        # we might have trailing nils in our children
        tree_val = AryExt[Array.new(@children.size)]
        (0..@offset).each do |idx|
          tree_val[idx] = @children[idx].tree
        end
        tree = ParseTree.new(:concat, symbol_name, @production_id, tree_val)
        @tree = tree if @done
        tree
      end
    end
  end
end
