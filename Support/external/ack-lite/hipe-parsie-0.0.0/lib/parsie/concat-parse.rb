module Hipe
  module Parsie
    class ConcatParse

      include NonterminalParsey

      extend Hookey
      has_hook_once :when_becomes_ok
      has_hook_once :after_gets_parse_id, :set_hook_with=>:after_gets_parse_id

    public
      attr_reader :parse_id, :satisfied_offset, :final_offset
      attr_reader :children # maybe only for recursive reference

    private
      attr_reader :start_offset, :prev_ok, :production_id, :current

    public

      def initialize production, ctxt, parent, &block
        yield(self) if block_given?
        @production_id = production.production_id
        @context_id = ctxt.context_id
        @done = nil
        @ok = nil
        @current = []
        self.parent_id = parent.parse_id
        @zero_map = production.zero_width_map
        @zero_width = production.zero_width?
        @satisfied_offset = production.satisfied_offset
        @final_offset = production.final_offset
        @children = nil # set at note4
        @start_offset = :not_set # 'set' at :note3
        @parse_id = Parses.register self
        run_hook_onces_after_gets_parse_id{|hook| hook.call(self) }
        locks_init
      end

      def parse_type;      :concat end
      def parse_type_short; 'c'    end
      def zero_width?; @zero_width end
      def is_the_empty_list?; @children.empty? end

      # about our @children: (note4:.)
      # - we always have an array the same size as the number of children
      #    of our corresponding nonterminal symbol (production),
      #    the array size does not correspond to the number of matched symbols.
      # - this array starts out as populated with all
      #    ones that we don't 'get to' will remain the NilParse singleton
      #
      # about our @start_offset (note3:.)
      # - 'current children' is the one or more of our children that
      #    is/are accepting tokens (when we have some children that are possibly
      #    zero width, e.g. /(?:foo)*/, then we may need to distrubute the current
      #    token to multiple children to determine the 'winner').
      #    the @start_offset is the beginning of this (changing) range.
      # - the start offset will point to an imaginary index after the end of
      #    our children array when the parse has reached the end of the array,
      #    e.g. if this body of this concat-production is the empty list,
      #    the @start_offset will be 0.  if it is ["foo", "bar"] and it is finished,
      #    and satisfied, the @start_offset will be 2.
      #
      # note7: pattern: we always use accessor methods except when setting ?
      #
      def build_children! opts={}
        if depth.nil?
          no("where's my depth?")
        end
        prod_childs = production.children
        @children = ArrayExtra[Array.new(prod_childs.size, NilParse)]
        if children.any?
          @start_offset = 0
          build_current_children_and_evaluate! opts
        else
          build_no_children!
        end
        @prev_ok = ok?
      end

      def each_existing_child &block
        idx = first_nil_parse_index_assert
        (0..idx-1).each do |i|
          block.call(@children[i], i)
        end
        nil
      end

      # @todo i don't know how we should take done etc into acct
      def expecting
        resp = (done? && ok?) ? [] :
          current_children.map(&:expecting).flatten.uniq
        resp
      end

      def inspct_extra(ll,ctx,opts)
        inspct_attr(ll,%w(@current @start_offset @last_look))
      end

      def _unparse arr
        no("no unparse if not ok") unless ok?
        idxs = (0..start_offset).map
        idxs.each do |idx|
          next unless children[idx]
          children[idx]._unparse arr
        end
        nil
      end

      # hacks to let visitors in ''very experimental''
      def _start_offset= offset
        fail("who dares set offset as such? #{offset}") unless
          offset.kind_of?(Fixnum)
        @start_offset = offset
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

      def take! foo
        Debug.puts "#{indent}#{short}.take! #{foo.inspect}" if Debug.verbose?
        @last_take = foo
        d = pop_cached_look_decision foo
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
        # note that when we are at the last child and it is closed,
        # our offset get set to one greater than the last valid offset (:note3)
        @start_offset = d2.open? ? d.wanter_idx : d.wanter_idx + 1
        build_current_children_and_evaluate!
        d2 = Decision.new
        d2.ok = ok?
        d2.done = done?
        d2.wants = true

        unless d2.equivalent?(d)
          no("broken promises: "+d.diff(d2).inspect)
        end

        if Debug.verbose?
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

      def tree
        no("no asking for tree if not ok") unless ok?
        return @tree if (done? && @tree)
        # we might have trailing nils in our children
        tree_val = ArrayExtra[Array.new(@children.size, NilParse)]
        if :the_empty_list==start_offset
          # we are cool, leave it as is
        elsif :not_set==start_offset
          debugger; 'we should never see this now!'
          if children.any?
            no("why is start offset not set when you are asking for tree?")
          end
        else
          stop_here = [children.length-1, start_offset].min
          (0..stop_here).each do |idx|
            child = children[idx]
            if child.nil?
              debugger; 'what did you do wrong silly goose?'
            elsif child.is_nil_parse?
              debugger; 'x'
              # these should always be at end? will they?
            else
              tree_val[idx] = children[idx].tree
            end
          end
        end
        tree = ParseTree.new(:concat, symbol_name, production_id, tree_val)
        @tree = tree if done?
        tree
      end

      # at the time of this writing this guy is public only for
      # RecursiveReference
      def look_decision token
        @last_look = token # just for debugging
        d = Decision.new
        d.wanter_idx, d.child_response = wanter_index_and_response(token)
        if ! d.wanter_idx
          d.ok = ok?
          d.done = done?
          d.wants = false
        else
          # we would adjust our offset based on whether or not
          # the interested child would still be open
          d.wants = true
          if d.wanter_idx > final_offset
            d.done = true
          elsif d.wanter_idx < final_offset
            d.done = false
          else
            d.done = d.child_response.done?
          end

          if d.wanter_idx > satisfied_offset
            d.ok = true
          elsif d.wanter_idx < satisfied_offset
            d.ok = false
          else
            d.ok = d.child_response.ok?
          end
        end
        d.assert_complete
        cache_look_decision(token, d)
        d
      end

      # this is experimental not sure don't know hack
      # the problem is if the child is open and ok, we need
      # to move forward.  The big issue is .. making sure only one
      # child gets the cheeze.  and when to move forward
      # attotw public only for RecursiveReference
      #
      def build_current_children_and_evaluate! opts={}
        these_asserts
        @current.clear
        if (@start_offset > final_offset) # see :note3
          @done = true
          evaluate_ok!
          return nil
        end
        @ok = nil
        @done = false
        @children_productions = production.children
        @ctxt = parse_context
        (start_offset..@children.length-1).each do |idx|
          @current.push idx
          break unless build_this_child_and_keep_going?(idx, opts)
        end
        @children_productions = nil
        @ctxt = nil
        evaluate_ok!
        nil
      end

      def release!
        clear_self!
        parent_clear!
        production.release_this_resetted_parse self
      end

    private

      # find the index of the first NilParse and assert
      # the structure. if no children are nil then return
      # one after the last index.
      #
      def first_nil_parse_index_assert
        idx = @children.index{|x| x.is_nil_parse? }
        if idx.nil?
          return @children.length
        end
        bad1 = (0..idx-1).map{|i|
          @children[i].is_nil_parse? ?
          [i,@children[i]] : nil
        }.compact
        bad2 = (idx..@children.length-1).map{|i|
          @children[i].is_nil_parse? ?
          nil : [i,  @children[i]]
        }.compact
        bads = bad1 + bad2
        if bads.any? then no(
          "found nil parses or non where we didn't expect to:" <<
          "i am #{short} and these are my bad children: " << (
            bads.map{|b| "at #{b[0]}: #{b[1].short}"}.join(';')
          )
        ) end
        idx
      end

      def build_no_children!
        @start_offset = :the_empty_list
        @done = true
        @ok = true
      end

      def clear_self!
        @done = @ok = nil
        @current = []
        @ui = nil
        children.each_with_index do |c, i|
          next if c.is_nil_parse?
          if c.is_reference?
            c.to_tombstone!
            children[i] = NilParse
          else
            c.clear_self!
          end
        end
      end

      def build_this_child_and_keep_going? idx, opts
        child = @children[idx]
        if child.is_nil_parse?
          child = @children_productions[idx].build_parse(@ctxt, self, opts)
          @children[idx] = child
        end
        if @zero_map[idx]
          # the child is possibly zero width so we need to
          # include any of its right siblings in the current list too
          return true
        end
        if child.respond_to?(:done?) && child.done?
          # children who are done should never stay in the current list.
          no("never")
        end
        if child.is_reference?
          # not sure about this @todo
          return false
        end
        if child.ok?
          return true
        end
        false # for some reason or another we want the current list to stop here
      end

      def evaluate_ok!
        @ok = false
        if start_offset >= satisfied_offset
          sat = children[satisfied_offset]
          if sat.is_nil_parse?
            # stay not ok
          elsif sat.is_reference?
            if sat.target.ok_known?
              if sat.target.ok?
                RootParse.ins
                # self.validate_around
                debugger; 'help?'
              else
                # recursive reference target is known not to be ok
                # stay not ok i guess
              end
            else
              # it is unknown whether it is ok or not.
              # stay not ok i guess
            end
          elsif sat.ok?
            @ok = true
          end
        end
        nil
      end

      def these_asserts
        no('never') unless children.any?
        no('never') unless start_offset.kind_of?(Fixnum)
      end

      def current_children
        current.map{|idx| children[idx]}
      end

      # note9: - if we wanted to get really cracked out we would deal with
      #         handling multiple interested children in the running in concats.
      #         but for now, such scenarios should be built into unions not concats.
      #         per this we only return the first interested child
      #         note this one itself should not change any state
      def wanter_index_and_response token
        found_idx = found_response_code = found = false
        look_lockout do
          current.each do |idx|
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
    end
  end
end
