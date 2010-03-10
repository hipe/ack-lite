module Hipe
  module Parsie
    class ConcatParse

      include NonterminalParsey, NonterminalInspecty, StrictOkAndDone,
        FaileyMcFailerson, Childable

      extend Hookey
      has_hook_once :when_becomes_ok

      attr_reader :parse_id # make sure this is set in constructor
      attr_accessor :children, :final_offset, :satisfied_offset

      def initialize production, ctxt
        @production_id = production.production_id
        @context_id = ctxt.context_id
        @parse_id = Parses.register self
        @start_offset = :not_set
        @done = nil
        @ok = nil
        @current = []
        @zero_width_map = production.zero_width_map
        @zero_width = production.zero_width?
        @satisfied_offset = production.satisfied_offset
        @final_offset = production.final_offset
        locks_init
      end

      # private
      def reset!
        @parent_id = nil
        @done = @ok = nil
        @currrent = []
        @children.each_with_index do |c, i|
          next if c.nil?
          if c.kind_of? Reference
            c.to_tombstone!
            @children[i] = nil
          else
            c.reset!
          end
        end
      end

      def release!
        reset!
        production.release_this_resetted_parse self
      end

      def zero_width?; @zero_width end

      def build_children! opts={}
        prod_childs = production.children
        @children = AryExt[Array.new(prod_childs.size)]
        build_next_children_and_evaluate! opts
        @prev_ok = @ok
      end

      def build_empty_children!
        @children = AryExt[Array.new(production.children.size)]
      end

      def build_next_children_and_evaluate! opts={}
        if 0 == @children.length
          @start_offset = false
          @done = true
          @ok = true
        else
          @current.clear
          @start_offset = 0 if @start_offset == :not_set
          if (@start_offset>@final_offset)
            @done = true
          else
            @done = false
            (@start_offset..@children.length-1).each do |idx|
              @current << idx
              break if @zero_width_map[idx] == false
            end
            build_current! opts
          end
          @ok = (@start_offset >= @satisfied_offset) &&
            @children[@satisfied_offset].ok?
        end
      end

      # @todo i don't know how we should take done etc into acct
      def expecting
        resp = (@done && @ok) ? [] :
          current_children.map(&:expecting).flatten.uniq
        resp
      end

      def current_children
        @current.map{|idx| @children[idx]}
      end

      def build_current! opts={}
        prod = production.children
        ctxt = parse_context
        @current.each do |idx|
          if (@children[idx].nil?)
            @children[idx] = prod[idx].build_parse ctxt, opts
            @children[idx].parent_id = parse_id
          else
            puts("child was already there") if Debug.true?
          end
        end
        nil
      end

      # per note9 we only return the first interested child
      def wanter_index_and_response token
        wanter = false
        child_resp = nil
        wanter_idx = nil
        look_lockout do
          @current.each do |idx|
            child = @children[idx]
            child_resp = child.look token
            if (0 != WANTS & child_resp)
              wanter = child
              wanter_idx = idx
              break
            end
          end
        end
        if wanter_idx
          [wanter_idx, child_resp]
        else
          [nil, nil]
        end
      end

      class Decision < Struct.new(:ok, :done, :want)
        include Decisioney, Misc # desc_bool
        def response
          ok_bit   = ok ? SATISFIED : 0
          open_bit = done ? 0 : OPEN
          want_bit = want ? WANTS : 0
          return want_bit | ok_bit | open_bit
        end
        alias_method :ok?, :ok
        alias_method :done?, :done
        alias_method :want?, :want
        def inspct_tiny
          them = %w(ok done)
          them << 'want' unless want.nil?
          "("<<(them.map{|x| desc_bool(x)}*',')<<")"
        end
      end

      def look token
        puts "#{inspct_tiny}.look #{token.inspect}.." if Debug.look?
        look_decision(token).response
      end

      def look_decision(token)
        @last_look = token # just for debugging
        decision = Decision.new
        wanter_idx, child_resp = wanter_index_and_response(token)
        if ! wanter_idx
          decision.ok = @ok
          decision.done = @done
          decision.want = false
        else
          # we would ajust our offset based on whether or not
          # the interested child would still be open
          child_still_open = (0 != OPEN & child_resp)
          hypothetic_next_index = wanter_idx + 1
          i_am_done = hypothetic_next_index >= @final_offset
          i_am_ok = hypothetic_next_index >= @satisfied_offset
          decision.ok = i_am_ok
          decision.done = i_am_done
          decision.want = true
        end
        if Debug.look?
          puts( "#{inspct_tiny}.look #{token.inspect} was: "<<
            decision.inspct_tiny
          )
        end
        decision
      end

      def take! token
        puts "#{inspct_tiny}.take! #{token.inspect}" if Debug.true?
        @last_take = token
        wanter_idx, child_resp = wanter_index_and_response(token)
        no("never") unless wanter_idx # there are lockouts and stuff
        child_resp = nil
        take_lockout do
          child_resp = @children[wanter_idx].take! token
        end
        child_open = (0 != OPEN & child_resp)
        child_satisfied = (0 != SATISFIED & child_resp)
        @start_offset = child_open ? wanter_idx : wanter_idx + 1
        build_next_children_and_evaluate!
        decision = Decision.new(@ok, @done)
        if Debug.true?
          puts( "#{inspct_tiny}.take! #{token.inspect} BEFORE HOOKS was: "<<
            " #{decision.inspct_tiny}")
        end

        if decision.ok? && ! @prev_ok
          @prev_ok = true
          run_hook_onces_when_becomes_ok do |hook|
            hook.call self, decision, token
          end
        end
        decision.response
      end

      def inspct_extra(ll,ctx,opts)
        inspct_attr(ll,%w(@current @start_offset @last_look))
      end

      def _unparse arr
        no("no unparse if not ok") unless @ok
        idxs = (0..@start_offset).map
        idxs.each do |idx|
          next unless @children[idx]
          @children[idx]._unparse arr
        end
        nil
      end

      def tree
        no("no asking for tree if not ok") unless @ok
        return @tree if (@done && @tree)
        # we might have trailing nils in our children
        tree_val = AryExt[Array.new(@children.size)]
        if false==@start_offset
          no("no") unless tree_val.size == 0
        else
          (0..@start_offset).each do |idx|
            child = @children[idx]
            if child.nil?
              # tree_val[idx] = nil
              next
            else
              tree_val[idx] = @children[idx].tree
            end
          end
        end
        tree = ParseTree.new(:concat, symbol_name, @production_id, tree_val)
        @tree = tree if @done
        tree
      end

      # hacks to let visitors in
      def _start_offset; @start_offset end
      def _start_offset= offset; @start_offset = offset end
    end
  end
end
