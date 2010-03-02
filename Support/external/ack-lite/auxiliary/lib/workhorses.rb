module Hipe
  module Parsie
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
      def build_children!
        context = parse_context
        @children = production.children.map do |sym|
          sym.spawn context
        end
        AryExt[@children]
        # in the running is an *ordered* list of ids (ordered by precedence)
        # that are not done (still accepting). doesn't matter if they are ok
        @in_the_running = (0..@children.length-1).map
      end
      # @todo the below should take into account in the running!
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

      # always set done and ok
      def look token
        puts "#{inspct_tiny} sees token \"#{token}\"" if Debug
        no("won't look when done") if @done
        look_lock
        @done = nil; @prev_ok = @ok;  @ok = nil
        idx_ok   = []; idx_done = []; skipped = []
        @in_the_running.each do |idx|
          child = @children[idx]
          wip = catch(:look_wip) do
            child.look(token)
            nil
          end
          if ! wip
            idx_ok   << idx if child.ok?
            idx_done << idx if child.done?
          elsif wip[:pid] != @parse_id
            throw :look_wip, wip
          else
            # see note5 ?
            puts("BOUNCED when #{token.inspect} was showed by "<<
            " #{inspct_tiny} to #{child.inspct_tiny}") if Debug
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
          "#{token}") if Debug
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
          # no('why is ok not set if we have looked?')
          puts "warning blah blah" if Debug
        end
        @ok = !! @children.detect{|x| x.ok? }
      end

      def done?
        # you are done iff all of your children are done
        return @done unless @done.nil?
        if @have_looked
          puts "Warning! blah blah" if Debug
          # raise no('why is done not set if we have looked?')
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

      def reference_indexes
        @children.each_with_index.select do |child,idx|
          child.kind_of? ParseReference
        end.map{|foo| foo[1]}
      end

      def prune_references!
        remove = reference_indexes
        @in_the_running -= remove
        removed = []
        remove.reverse.each do |idx|
          removed << @children.delete_at(idx)
        end
        @ok = @children.map{|c| c.ok?}.size > 0
        @done = @in_the_running.size == 0
        removed
      end

      def _add_not_done_child! child
        @in_the_running << @children.size
        @children << child
        nil
      end
    end


    class ConcatParse
      include AggregateParsey, AggregateParseInspecty, LookieLocky, NaySayer
      attr_reader :parse_id # make sure this is set in constructor
      attr_accessor :children
      def initialize production, ctxt
        @production_id = production.production_id
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

      def build_empty_children!
        @children = Array.new(production.children.size)
        AryExt[@children]
        @ok_index   = @children.length - 1 # @todo trailing zero
        @final_index = @children.length - 1
        nil
      end

      def build_children!
        build_empty_children!
        prod = production
        no('test empty children') if prod.children.size == 0
        @children[0] = prod.children[0].spawn(parse_context)
        nil
      end

        # _build_children
        # # *after* it processes the child at that index, it will be ..
        # @ok_index   = @children.length - 1 # @todo trailing zero
        # @final_index = @children.length - 1
      # end
      #
      # def make_empty_children!
      # end

      def look token
        puts "#{inspct_tiny} sees token \"#{token}\"" if Debug
        no("concat won't look when done") if @done
        look_lock
        @last_token_seen = token
        # before we change our state ..
        @children.select{|c| c && c.hypothetical?}.map(&:kidnap!)
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
          # if @post_evaluate
          #   debugger
          #   @post_evaluate.call
          #   @post_evaluate = nil
          # end
        end
        look_unlock
      end

      def _set_offset! offset
        no("don't set offset to nil") unless offset
        @offset = offset
      end

      def advance_over_recursive_child!
        curr = @children[@offset]
        was_done = curr.done?
        no("not going to advance over recusive child unless "<<
        "it is ok") unless curr.ok?
        no("have never dealt with when recursive child is final element") if
          @offset == @final_index
        if ! was_done
          # then split off a new self and add it to the parent union
          hyp = curr._hypothetic
          victim = hyp.orig_parent
          nu = ConcatParse.new production, parse_context
          nu.build_empty_children!
          nu.children[@offset] = ParseReference.new victim
          nu._set_offset! @offset
          victim._add_not_done_child! nu
          no('no') if @post_evaluate
          # @post_evaluate = lambda{ nu.re_evaluate! }
          # debugger;
          'you want to split '
          # ...
          refs = curr.prune_references! # @todo i thought we want these ?
        else
          no("haven't dealt with current being done before") if was_done
        end
        _increment_offset!
        nil
      end

      def re_evaluate!
        print "#{self.inspct_tiny} (re)evaluates with: " if Debug
        no("tried to evaluate twice on the same token!") if
          (@last_evaluate==@evaluate_tic)
        @last_evaluate = @evaluate_tic
        curr = @children[@offset]
        meth = if curr.done?
          curr.ok? ? :advance_done_and_ok : :advance_done_and_not_ok
        else
          curr.ok? ? :advance_not_done_and_ok : :advance_not_done_and_not_ok
        end
        print "#{meth}\n" if Debug
        send meth
      end

      def advance_done_and_ok # our favorite state
        # the child we just evaluated was done and ok,
        # we move forward or we are finished!
        @ok   = @offset >= @ok_index
        @done = @offset >= @final_index
        if @offset < @final_index
          _increment_offset!
        end
        nil
      end

      def _increment_offset!
        @offset += 1
        no("no") if @offset > @final_index
        _make_current_parser! if @children[@offset].nil?
        'make sure new child is blah'
      end

      def _make_current_parser!
        chldrn = production.children
        nu = chldrn[@offset].spawn(parse_context)
        @children[@offset] = nu
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
          print "#{self.inspct_tiny} CREATES SPAWN: " if Debug
          nu = curr.target.spawn_hypothetical self
          print "#{nu.inspct_tiny}\n" if Debug
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
  end
end
