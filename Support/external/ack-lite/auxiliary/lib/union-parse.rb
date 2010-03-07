module Hipe
  module Parsie
    class UnionParse

      include NonterminalParsey, NonterminalInspecty, FaileyMcFailerson,
        StrictOkAndDone

      extend Hookey

      has_hook_once :after_take!

      attr_reader :parse_id # make sure this is set in constructor
      attr_reader :children # debug gin

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
        decided! Decision.based_on(in_the_running)
      end

      # this wraps all of our ambigity logic, etc
      class Decision < Struct.new(:idxs_want, :idxs_satisfied,
        :idxs_open, :idxs_closed);

        include Decisioney, Misc # desc_bool

        def self.based_on list, &block
          return self.based_on_using(list, &block) if block_given?
          decision = Decision.new
          list.each do |(child, idx)|
            if child.done?
              decision.idxs_closed << idx
            else
              decision.idxs_open << idx
            end
            if child.ok?
              decision.idxs_satisfied << idx
            end
          end
          decision
        end

        def initialize
          self.idxs_open = []
          self.idxs_satisfied = []
          self.idxs_want = []
          self.idxs_closed = []
        end

        def self.based_on_using list, &block
          decision = Decision.new
          list.each do |(child, idx)|
            resp = block.call child, idx
            next if resp == :skip
            decision.merge_in_response! resp, idx
          end
          decision
        end

        def merge_in_response! resp, idx
          if 0 != OPEN & resp
            idxs_open << idx
          else
            idxs_closed << idx
          end
          if 0 != SATISFIED & resp
            idxs_satisfied << idx
          end
          if 0 != WANTS & resp
            idxs_want << idx
          end
          nil
        end

        def idx_done_and_ok
          self.idxs_satisfied & self.idxs_closed
        end

        def done?
          no_more_open = self.idxs_open.size == 0
          no_more_open
          # ok_and_done_this_round = self.idx_done_and_ok.size > 0
          # no_more_open || ok_and_done_this_round
        end

        def ok?
          self.idxs_satisfied.size > 0
        end

        def want?
          self.idxs_want.size > 0
        end

        def response
          want_bit = self.want? ? WANTS : 0
          ok_bit = self.ok? ? SATISFIED : 0
          open_bit = self.done? ? 0 : OPEN
          want_bit | ok_bit | open_bit
        end

        def inspct_tiny
          '('<< (%w(want? ok? done?).map{|x| desc_bool(x)}.join(', ')) << ')'
        end
      end

      def decided! decision
        @in_the_running -= decision.idxs_closed
        @ok = decision.ok?
        @done = decision.done?
      end

      def not_my_wip
        no("we caught a wip that is not ours. we are pretty "<<
        "sure we want to just throw it but we need to test this"
        )
      end

      def look_decision token
        puts "#{inspct_tiny}.look_decision #{token.inspect}.." if Debug.look?
        decision = nil
        wips = []
        look_lockout do
          decision = Decision.based_on(in_the_running) do |child,idx|
            child_resp = nil
            my_resp = nil
            wip = catch :wip_look do
              child_resp = child.look token
              nil
            end
            if wip
              if wip[:pid] != @parse_id
                not_my_wip
              else
                wips << [wip,idx]
                my_resp = :skip
              end
            else
              my_resp = child_resp
            end
            my_resp
          end
        end
        wips.each do |(wip,idx)|
          wip[:callback].call self, decision, idx, token
        end
        if Debug.look?
          puts("#{inspct_tiny}.look_decision on #{token.inspect} was: "<<
                decision.inspct_tiny)
        end
        decision
      end

      def look token
        @last_look = token
        look_decision(token).response
      end

      def take! token
        look = look_decision token
        no("won't take when don't want") unless look.want?
        take = nil
        wants = slice look.idxs_want
        @in_the_running = look.idxs_want | look.idxs_open
        take_lockout do
          take = Decision.based_on(wants) do |child,idx|
            child.take! token
          end
        end
        take.idxs_open |= look.idxs_open

        run_hook_onces_after_take! do |block|
          block.call(self, take, token)
        end

        decided! take
        take.response
      end

      def slice(idxs)
        idxs.map{|idx| [@children[idx], idx] }
      end
      def in_the_running
        slice @in_the_running
      end
      def winners; @children.select{|x| x.done? && x.ok? } end

      def tree
        @tree ||= begin
          if (winner = self.winner)
            tree_from_winner winner
          else
            false # or throw error?
          end
        end
      end

      def _unparse arr
        no("no unparse if not ok") unless @ok
        winner = self.winner
        if winner
          winner._unparse(arr)
        else
          no("no")
        end
        nil
      end

      def winner
        winners = self.winners
        if winners.size > 1
          disambiguate_or_raise winners
        elsif winners.size == 0
          false # or throw error?
        else
          winners[0]
        end
      end

      # @todo the below should take into account in the running!
      def expecting
        resp = []
        @children.each_with_index do |c,i|
          resp += c.expecting
        end
        resp
      end

      # unlike concat trees, a union tree selects its one winner and uses the
      # tree of that winning child to represent its tree
      def tree_from_winner winner
        winner.tree
        # my_val = winner.tree
        # ParseTree.new(:union, symbol_name, @production_id, my_val)
      end

      def inspct_extra(ll,ctx,opts)
        inspct_attr(ll,%w(@in_the_running @last_look))
      end

      #
      # dismbiguating parse trees:
      # if multiple matched and one is the empty concat (empty match)
      # discount it.  if multiple terminals matched, use the first one.
      # otherwise it is considered an unresolvable ambiguity.
      #
      def disambiguate_or_raise winners
        terminals = []
        non_empty_non_terminals = []
        winners.each_with_index do |winner, idx|
          if winner.kind_of? Terminesque
            terminals << idx
          elsif winner.kind_of?(ConcatParse) && winner.children.size == 0
              # discount it
          else
            non_empty_non_terminals << idx
          end
        end
        fail_msg = nil
        if terminals.size > 0
          if  non_empty_non_terminals.size > 0
            fail_msg = "Had more than one terminal and more than one " <<
            "non-empty non-terminal"
          else
            return winners[terminals.first]
          end
        else
          if non_empty_non_terminals.size > 1
            fail_msg = "Had more than one non-emtpy non-terminal"
          elsif non_empty_non_terminals.size == 1
            return winners[non_empty_non_terminals.first]
          else
            fail_msg = "huh?"
          end
        end
        $po = self
        full_fail_msg = "ambiguous parse tree - #{fail_msg}. "<<
          "Parse object set to $po"
        raise ParseFail.new(full_fail_msg)
      end

      # only for hacking by visitors
      def _in_the_running; @in_the_running end
      def _done= foo; @done = foo end
    end
  end
end

