module Hipe
  module Parsie
    class ConcatParse

      include NonterminalParsey, NonterminalInspecty, StrictOkAndDone,
        FaileyMcFailerson, Childable

      extend Hookey
      has_hook_once :when_becomes_ok

      attr_reader :parse_id # make sure this is set in constructor
      attr_accessor :children, :final_offset, :satisfied_offset

      def initialize production, ctxt, parent
        @parse_id = Parses.register self
        self.parent_id = parent.parse_id
        @production_id = production.production_id
        @context_id = ctxt.context_id
        @start_offset = :not_set
        @done = nil
        @ok = nil
        @current = []
        @zero_map = production.zero_width_map
        @zero_width = production.zero_width?
        @satisfied_offset = production.satisfied_offset
        @final_offset = production.final_offset
        locks_init
      end

      def parse_type; :concat end
      def parse_type_short; 'c' end

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
        if depth.nil?
          no("where's my depth?")
        end
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
              @current.push idx
              # this is experimental not sure don't know hack
              # the problem is if the thing is open and ok, we need
              # to move forward.  The big issue is .. making sure only one
              # child gets the cheeze.  and when to move forward
              # start_offset is they key, right?

              # it is non-zero width
              if @zero_map[idx] == false
                child = @children[idx]
                if child
                  if child.done?
                    no("why is a closed child in the running here? "<<
                      "wasn't start_offset advanced somewhere else?"
                    )
                  end
                  if child.ok?
                    # child is ok, keep it in the running but advance current
                    # ''not sure''
                  else
                    break # child is not ok, stay here
                  end
                else
                  break # there is no child populated here yet, stay here (?)
                end
              else
                # this is a zero width child, (it can match on no tokens)
                # so keep cycling thru other children to build current
              end
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
            @children[idx] = prod[idx].build_parse ctxt, self, opts
          else
            Debug.puts("child was already there") if Debug.true?
          end
        end
        nil
      end

      # per note9 we only return the first interested child
      # note this one itself should not change any state
      def wanter_index_and_response token
        found_idx = found_response_code = found = false
        look_lockout do
          @current.each do |idx|
            child = @children[idx]
            code = child.look token
            resp = Response[code]
            if (resp.wants?)
              found = true;
              found_idx = idx
              found_response_code = code
              break
            end
          end
        end
        if found
          response = Response[found_response_code]
          [found_idx, response]
        else
          [nil, nil]
        end
      end

      def look token
        if Debug.look?
          Debug.puts "#{indent}#{short}.look (start) #{token.inspect}"
        end
        d = look_decision(token)
        if Debug.look?
          Debug.puts("#{indent}#{short}.look #{token.inspect} was: "<<
          d.inspct_for_debugging)
        end
        d.response
      end

      class Decision
        extend AttrAccessors
        boolean_accessor :open, :satisfied, :wants
        include Decisioney
        attr_accessor :wanter_idx, :child_response_code,
          :child_response, :child_still_open
        def short
          them = %w(ok done)
          them << 'wants' unless wants.nil?
          "("<<(them.map{|x| desc_bool(x)}*',')<<")"
        end
      end

      def look_decision token

        @last_look = token # just for debugging
        d = Decision.new
        d.wanter_idx, d.child_response = wanter_index_and_response(token)
        if ! d.wanter_idx
          d.ok = @ok
          d.done = @done
          d.wants = false
        else
          # we would adjust our offset based on whether or not
          # the interested child would still be open
          d.wants = true
          if d.wanter_idx > @final_offset
            d.done = true
          elsif d.wanter_idx < @final_offset
            d.done = false
          else
            d.done = d.child_response.done?
          end

          if d.wanter_idx > @satisfied_offset
            d.ok = true
          elsif d.wanter_idx < @satisfied_offset
            d.ok = false
          else
            d.ok = d.child_response.ok?
          end
        end
        d.assert_complete
        d
      end

      def take! foo
        Debug.puts "#{indent}#{short}.take! #{foo.inspect}" if Debug.true?
        @last_take = foo
        d = look_decision foo
        if ! d.wants?
          debugger; 'wtf'
          no("cannot take what i do not want")
        end
        code_actual = nil
        take_lockout{ code_actual = @children[d.wanter_idx].take!(foo) }
        d2 = Response[code_actual]
        unless d.child_response.equivalent? d2
          diff = d.child_response.diff(d2)
          msg = "broken promises: #{diff.inspect}"
          no(msg)
        end
        @start_offset = d2.open? ? d.wanter_idx : d.wanter_idx + 1
        build_next_children_and_evaluate!
        d2 = Decision.new
        d2.ok = @ok
        d2.done = @done
        d2.wants = true

        unless d2.equivalent?(d)
          no("broken promises: "+d.diff(d2).inspect)
        end

        if Debug.true?
          Debug.puts( "#{indent}#{short}.take! #{foo.inspect} "<<
            "BEFORE HOOKS was: #{d.short} (kept promises)")
        end

        if d2.ok? && ! @prev_ok
          @prev_ok = true
          run_hook_onces_when_becomes_ok do |hook|
            hook.call self, d2, foo
          end
        end

        d2.response
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
