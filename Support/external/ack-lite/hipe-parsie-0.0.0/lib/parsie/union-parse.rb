module Hipe
  module Parsie
    class UnionParse

      include NonterminalParsey, NonterminalInspecty, FaileyMcFailerson,
        StrictOkAndDone, Childable

      extend Hookey

      has_hook_once :after_union_take!

      attr_reader :parse_id # make sure this is set in constructor
      attr_reader :children # debug gin

      # note2 - this is only called in one place
      def initialize union, ctxt, parent
        @parse_id = Parses.register self
        self.parent_id = parent.parse_id
        locks_init
        @production_id = union.production_id
        @context_id = ctxt.context_id
        @done = nil; @ok = nil
        # in the running is an *ordered* list of ids (ordered by precedence)
        # that are not done (still accepting). doesn't matter if they are ok
        @in_the_running = false
      end
      def parse_type; :union end
      def parse_type_short; 'u' end

      def build_children! opts={}
        context = parse_context
        children_productions = production.children
        @children = AryExt[Array.new]
        children_productions.each_with_index do |child_production,idx|
          child = nil
          if opts[:child_hook]
            child = opts[:child_hook].call(self, child_production, idx, opts)
          else
            child = child_production.build_parse(context, RootParse)
          end
          if :skip_child != child
            @children << child
          end
        end
        @in_the_running = (0..@children.length-1).map
        decided! Decision.based_on(in_the_running)
      end

      # this wraps all of our ambigity logic, etc
      class Decision < Struct.new(
        :idxs_want, :idxs_satisfied,
        :idxs_open, :idxs_closed);

        def open;       self.idxs_open.size > 0      end
        def satisfied;  self.idxs_satisfied.size > 0 end
        def wants;      self.idxs_want.size > 0      end

        include Decisioney, Misc # desc_bool

        class << self
          def main_props
            %w(idxs_open idxs_satisfied idxs_want idxs_closed)
          end
        end

        def initialize
          self.idxs_open = []
          self.idxs_satisfied = []
          self.idxs_want = []
          self.idxs_closed = []
          @responses_ive_seen = {}
        end

        def self.based_on list, &block
          return self.based_on_using(list, &block) if block_given?
          decision = Decision.new
          list.each do |(child, idx)|
            if child.done?
              Debug.puts "#{$token} adding this index to idx closed: #{idx}" if
                Debug.true?
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

        def self.based_on_using list, &block
          decision = Decision.new
          list.each do |(child, idx)|
            resp = block.call child, idx
            next if resp == :skip
            decision.add_response! resp, idx
          end
          decision
        end

        def deep_dup
          # marshal load didn't like what we did to the constructor
          response = self.class.new
          self.class.main_props.each do |x|
            response.send("#{x}=",self.send(x).dup)
          end
          response
        end

        def deep_freeze!
          self.class.main_props.each do |x|
            self.send(x).freeze
          end
          freeze
          self
        end

        def add_response! resp, idx
          no("already seen respnose for #{idx}") if @responses_ive_seen[idx]
          @responses_ive_seen[idx] = true
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

        def inspct_tiny
          '('<< (%w(wants? ok? done?).map{|x| desc_bool(x)}.join(', ')) << ')'
        end
      end

      def decided! decision
        @in_the_running = decision.idxs_open.dup
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
        decision = Decision.new
        wips = []
        look_lockout do
          @in_the_running.each do |idx|
            child = @children[idx]
            child_resp = nil
            wip = catch :wip_look do
              child_resp = child.look token
              nil
            end
            if wip
              not_my_wip if wip[:pid] != @parse_id
              wips << [wip,idx]
            else
              decision.add_response! child_resp, idx
            end
          end
        end
        if wips.any?
          frozen_decision = decision.deep_dup.deep_freeze!
        end
        wips.each do |(wip,idx)|
          wip[:callback].call self, frozen_decision, decision, idx, token
        end
        if Debug.look?
          Debug.puts("#{inspct_tiny}.look_decision on #{token.inspect} was: "<<
                decision.inspct_tiny)
        end
        decision.assert_complete
        decision
      end

      def look token
        @last_look = token
        look_decision(token).response
      end

      def take! token
        look = look_decision token
        no("won't take when don't want") unless look.wants?
        take = Decision.new
        take_lockout do
          look.idxs_want.each do |idx|
            child = @children[idx]
            child_resp = child.take! token
            take.add_response! child_resp, idx
          end
        end
        run_hook_onces_after_union_take! do |block|
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
        @in_the_running.each do |idx|
          resp += @children[idx].expecting
        end
        resp
        # resp = []
        # @children.each_with_index do |c,i|
        #   resp += c.expecting
        # end
        # resp
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
        if terminals.size >= 1
          tsize = terminals.size
          if  non_empty_non_terminals.size > 1
            ntsize = non_empty_non_terminals.size
            fail_msg = "Had more than one terminal (#{tsize}) "<<
              " and more than one " <<
              "non-empty non-terminal (#{ntsize})"
          else
            return winners[terminals.first]
          end
        else
          if non_empty_non_terminals.size > 1
            fail_msg = "Had more than one non-emtpy non-terminal"
          elsif non_empty_non_terminals.size == 1
            return winners[non_empty_non_terminals.first]
          else
            fail_msg = "i don't know what to do here."
          end
        end
        $po = self
        full_fail_msg =
          "#{inspct_tiny} had ambiguous parse tree - #{fail_msg}. "<<
          "Parse object set to $po"
        raise ParseFail.new(full_fail_msg)
      end

      def indexes_not_ok
        children.to_enum.with_index.map{|c,i| i unless c.ok?}.compact
      end

      #
      # how/where this is invoked and what it means is experimental
      #
      #
      def prune! opts
        these = []
        @children.each_with_index do |c, i|
          next if @in_the_running.include?(i)
          these.push(i)
        end
        @in_the_running = :pruned
        these.reverse!
        num = 0
        these.each do |idx|
          child = @children[idx]
          if ! child.kind_of?(Tombstone)
            child.release!
          end
          num += 1
          @children.delete_at idx
        end
        num
      end

      # only for hacking by visitors
      def _in_the_running; @in_the_running end
      def _done= foo; @done = foo end
    end
  end
end

