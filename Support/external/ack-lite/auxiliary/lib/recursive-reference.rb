#
# This is where all the hacking goes for dealing with left-recursive crap.
# All of this is experimental and most (if not all) of it is probably trash.
#
# We try to keep such code to a minimum elsewhere in the thing.
#
# RecursiveReference objects are created when, during the parse of a single
# token, more than one parse object is attempted to be made from the same
# production rule (during development this was only encountered with
# left-recursive symbols) (things will probably break in other similar but not
# the same cases)
#
# Without recursive references, recursive productions will try to build
# infinitely large parser trees.  (not parse trees, but parser trees)
# With recursive references, when the
# reference is asked to look at a token, it assumes that the node it
# references has already been visited (and is being visited presently), so
# this node cannot yet come to a decision about whether or not it wants the
# token.
#
# So instead it throws a "wip_look", which union parses are supposed to catch,
# and the union parse is supposed to continue evaluating its other children.
# Once the union parse finishes evaluating its non-recursive nodes (nodes
# that have children that refer to the same production that the union node
# is,) the union node calls a callback that was in the wip.
#
# This callback sees if the union node is satisfied as it is (without having
# dealt with this recursion.)  If it is, the recursive node knows that it can
# steal the satisfied child node of the union to make itself satisfied.
#
# There is ugliness on parsing the second good token, (consider the
# transformation that needs to occur between the two parse trees)
# This is what RecursiveReference deals with.
#
#
# At some point, magically thru the use of hooks we end up with one root
# union node with two concat node children.  the one on the left is
# built and done, and possibly deep; and the one on the right has two
# children: the firt child is a reference (plain reference not recursive
# reference) to the concat node on the left of the union, and its second
# child (children one day!??) is/are the terminals or non-recursive
# nodes it nees to fulfill.  once it starts taking tokens to fullfill
# its right side, it *steals* the left node, moves itself into the left
# position, and creates a new similar concat node, that itself has the
# same arrangement, and so on.
#
# in theory this is how the concat node is infinitely growable down
# and to the left.
#
# (There is a lot of hacking of the decision structures of the union)
#
# There is logical repetition in this file because it took a while to hook
# into making this thing itself a recursive algorithm

module Hipe
  module Parsie

    Stub = Object.new     # this is just used in temporary hacking
    class << Stub         # so we can get parse trees from fragmentary
      def ok?; false end  # parses.  ok to erase ?
      def done?; true end
    end

    CONCAT_INCREMENT = 1  # just to keep track of where we are using

    class Reference
      include Misc
      attr_accessor :parent_idx
      attr_reader :my_parse_id, :target_parse_id
      def initialize target_parse
        @target_parse_id = target_parse.parse_id
        @my_parse_id = Parses.register self
        @look_hack = nil
        @parent_idx = false
        @steal_idx = nil
        @idx_in_union = nil
      end
      def target
        Parses[@target_parse_id]
      end
      def inspct ctxt, opts
        sprintf("#<Reference%s->%s>", @my_parse_id, @target_parse_id)
      end

      #
      # gives source child to target parent at the indicated indexes,
      # leaving a ransom note or tombstone or something
      # the previous child that used to be at target is returned.
      # internals of the parent's done-ness is not dealt with
      # this might as well be a class method -- don't refer to
      # any instance variables here
      #
      def swapout_child src_parent, src_idx, tgt_parent, tgt_idx
        stolen = src_parent.children[src_idx]
        no('no') unless stolen
        displaced = tgt_parent.children[tgt_idx]
        no('no') unless displaced
        src_parent.children[src_idx] =
          %{stolen_by_#{tgt_parent.parse_id}}.to_sym
        tgt_parent.children[tgt_idx] = stolen
        displaced
      end

      #
      # put the new child in the old spot,
      # @return what was previously there (must be not nil)
      #
      def replace_child src_parent, src_idx, new_child
        old = src_parent.children[src_idx]
        no('no') unless old
        src_parent.children[src_idx] = new_child
        old
      end

      #
      # this is hackishly always called with that first recursive reference
      # as the receiver, so we always have a handle on the base union,
      # from which the tree grows down.
      # the union itself is never swapped out (it is root node in tests)
      # and the one RecursiveReference just floats around in memory forever.
      #
      def utter_insanity_concat concat
        new_one = ConcatParse.new(concat.production,concat.parse_context)
        new_one.build_empty_children!
        reference = Reference.new concat
        new_one.children[parent_idx] = reference
        new_one._start_offset = parent_idx + CONCAT_INCREMENT
        new_one.build_next_children_and_evaluate!
        new_one.hook_once_after_take! do |*args|
          step_4_after_concat_take!(*args)
        end
        new_one
      end

      #
      # the right concat node has just satisfied its right terminal token
      # and its left (first) child is a reference to its sibling to the left,
      # another concat node.  It needs to collapse the reference it has
      # (and steal the referrant)
      #
      def step_4_after_concat_take! concat, decision, token
        union = root_union; step_4_assertions root_union, concat
        ref = swapout_child union, idx_in_union, concat, idx_in_concat
        ref.make_tombstone!(concat.parse_id)
        junk_sym = swapout_child union, steal_idx, union, idx_in_union
        new_concat = utter_insanity_concat concat
        symbol = replace_child union, steal_idx, new_concat
        no('no') unless symbol.kind_of? Symbol
        union.hook_once_after_take! do |_, decision, token|
          replace_decision_indexes decision, steal_idx, idx_in_union
          no("no") if decision.idxs_open.include? steal_idx
          decision.idxs_open.push steal_idx
        end
      end

      #
      # this is where the hackey magic begins.  build new nodes
      # this is similar to logic elsewhere
      #
      def step_4_initial_after_concat_take! concat, decision, token
        union = root_union
        new_concat = utter_insanity_concat concat
        stolen = replace_child union, steal_idx, new_concat
        me = replace_child concat, idx_in_concat, stolen
        no('no') unless me.my_parse_id == my_parse_id
        # never see me again (actually i may live on infinitely)
        make_tombstone!
        no('no') if union._in_the_running.include? steal_idx
        union._in_the_running << steal_idx
        union._done = false
        union.hook_once_after_take! do |*args|
          step_5_initial_after_union_take!(*args)
        end
      end




      def step_4_assertions union, concat_rt
        no("just fix this. easy") unless union._in_the_running == [1]
        no("wuh happuh?") unless
          concat_rt.children[idx_in_concat].kind_of? Reference
        no("wuh happuh?") unless
          union.children[idx_in_union].parse_id ==
            concat_rt.children[idx_in_concat].target_parse_id
      end

      #
      # don't know if we need this
      #
      def remove_decision_indexes decision, value
        %w(idxs_satisfied idxs_open idxs_closed).each do |meth|
          arr = decision.send(meth)
          idxs = arr.to_enum.with_index.map do |v,i|
            i if v == value
          end.compact
          idxs.reverse.each{|idx| arr.delete_at(idx) }
        end
      end


      #
      # @todo maybe we don't need this after all
      # since we shuffled nodes around in the union parse, we need to
      # do the same shuffling to its decision structure
      #
      def replace_decision_indexes decision, right_idx, idx_in_union
        %w(idxs_satisfied idxs_open idxs_closed).each do |meth|
          decision.send(meth).map! do |idx|
            if idx == right_idx then idx_in_union
            elsif idx == idx_in_union then no("no!!!")
            else idx end
          end
        end
      end

      #
      # When a parse reference is no longer needed (when it is 'collapsed')
      # we leave a marker here for debugging.
      #
      def make_tombstone!(agent_msg=nil)
        msg = agent_msg ?
          ("reference_#{my_parse_id}_to_#{target_parse_id}" <<
           "_collapsed_by_#{agent_msg}") :
          ("tombstone_for_reference_#{my_parse_id}_to_#{target_parse_id}")
        Parses.replace!(my_parse_id, msg.to_sym)
      end
    end

    #
    # RecursiveReferences should only be created in one place, by non-termials
    # who are trying to build a parser that has already been built during the
    # lifetime of this token.   For now they have been tailored to a specific
    # arrangement of a left-recursive production.  We will need to try to
    # generalize or superclass elements of this for other similar scenarios
    # because as they are they will certainly fail for some grammars.
    #
    class RecursiveReference < Reference
      alias_method :idx_in_concat, :parent_idx
      def initialize target_parse
        super
        return not_union unless target_parse.kind_of? UnionParse
      end

      def idx_in_union
        no("no") unless @idx_in_union
        @idx_in_union
      end

      def root_union
        union = target
        no('no') unless union.kind_of?(UnionParse)
        union
      end

      def idx_in_union= idx
        no("no") if @idx_in_union && @idx_in_union != idx
        @idx_in_union = idx
      end

      def steal_idx
        no("no") unless @steal_idx
        @steal_idx
      end

      def steal_idx=foo
        no('no') if @steal_idx && @steal_idx != foo
        @steal_idx = foo
      end

      def not_union
        no("we need to develop this differently if we ever have "<<
        "recursive targets other than UnionParse.")
      end

      def inspct ctxt, opts
        sprintf("#<RecursiveReference%s->%s", @my_parse_id, @target_parse_id)
      end

      # the parent should already said it (?) no reason to repeat
      def expecting; [] end

      #
      # There is some cruft in here b/c we used to think that we
      # had to trigger look wips all the time.  We do with recursive
      # references, but not vanilla references.
      #
      def look token
        if @look_hack # this is step 1
          no("never")
          look_hack = @look_hack
          @look_hack = nil
          return look_hack
        else
          throw :wip_look, {
            :pid => target_parse_id,
            :callback => lambda{|*args|
              step_2_look_again(*args)
            }
          }
        end
      end

      #
      # you know that you could steal children, so take that into account
      # when your parent concat assesses you.  We want to know, "what would
      # the concat have said if i had been its satisfied child?".  Looks
      # aren't supposed to cause state changes.  This one does, guaranteed
      # to cause bugs
      #
      def step_2_look_again union, decision, idx, token
        self.idx_in_union = idx
        no("logical fallacy") if @look_hack
        if ! union.ok? # not sure about this step,
          # do we stay open indefinitely until the union without us
          # is ok? should we be looking at decision instead?
          no("logical fallacy") if decision.idxs_open.include?(idx)
          decision.idxs_open << idx
        else
          # we're calling this step 3?
          store_steal_idx union
          parent_concat = union.children[idx]
          step_3_hack_parent_concat_if_necessary parent_concat, token
          @look_hack = :NEVER
          dec = parent_concat.look_decision(token)
          decision.merge_in_response! dec.response, idx
        end
      end


      #
      # pre: your target union is ok (before even looking at the curr. tok.)
      # effectively tell the concat that its first child (the reference) is ok
      # by moving its starting offset over one, and hooking into its take
      #
      def step_3_hack_parent_concat_if_necessary parent, token
        assert_hackable parent
        so = parent._start_offset
        parent._start_offset = so + CONCAT_INCREMENT
        parent.build_next_children_and_evaluate!
        no('needs testing') if parent.done?
        parent.hook_once_after_take! do |*args|
          step_4_initial_after_concat_take!(*args)
        end
      end

      def assert_hackable concat
        no('no') if false == idx_in_concat
        no('no') unless concat.kind_of? ConcatParse
        so = concat._start_offset
        if so < idx_in_concat
          no('no')
        elsif so > idx_in_concat
          debugger ; 'probably ok just to return'
          no('no')
        else
          no('no') unless
            concat.children[idx_in_concat].my_parse_id == my_parse_id
        end
      end

      #
      # figure out which child we would steal when the time comes
      #
      def store_steal_idx union
        no("shouldn't do this more than once?") if @steal_idx
        oks = union.children.map(&:ok?)
        no("don't have logic for which children to steal of several") unless
          oks.select{|x| x==true}.size == 1
        idxs = oks.to_enum.with_index.map{|x,i| i if x}.compact
        no("no") unless idxs.size == 1
        self.steal_idx = idxs.pop
      end

      #
      # this is where the hackey magic begins.  build new nodes
      # this is similar to logic elsewhere
      #
      def step_4_initial_after_concat_take! concat, decision, token
        union = root_union
        new_concat = utter_insanity_concat concat
        stolen = replace_child union, steal_idx, new_concat
        me = replace_child concat, idx_in_concat, stolen
        no('no') unless me.my_parse_id == my_parse_id
        # never see me again (actually i may live on infinitely)
        make_tombstone!
        no('no') if union._in_the_running.include? steal_idx
        union._in_the_running << steal_idx
        union._done = false
        union.hook_once_after_take! do |*args|
          step_5_initial_after_union_take!(*args)
        end
      end

      #
      # hack the take decision to keep the thing open
      # put a breakpoint at the beginning and do a $p.insp when u run test 10
      # to see a clear picture of the decision as it stands and the decision
      # as it should stand.
      #
      def step_5_initial_after_union_take! union, take, token
        if take.idxs_open.include? idx_in_union
          # this occurs in page43 grammar
          debugger; "FIX ME? or not"
          # no('no')
        else
           take.idxs_open << steal_idx
        end
      end
    end
  end
end
