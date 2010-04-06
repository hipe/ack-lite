#
# This is where all the hacking goes for dealing with left-recursive crap.
# All of this is experimental and most (if not all) of it is probably trash.
#
# We try to keep such code to a minimum elsewhere in the thing.
#
# My policy on comments is "comment only when necessary to explain a
# complicated, unconventional or experimental feature.  (Avoid
# complicated, unconventional or experimental features.)"
# This file has a lot of comments.
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
# So instead it throws a "wip_look", (wip: work in progress)
# which union parses are supposed to catch,
# and the union parse is supposed to continue evaluating its other children.
# Once the union parse finishes evaluating its non-recursive nodes (nodes
# that have children that refer to the same production that the union node
# is,) the union node calls a callback that was in the wip.
#
# This callback take the union nodes's state as it would have been
# without the recursion, and evaluates the state of the concat node.
# Effectively the concat node blindly evaluates the recursive node
# not knowing that it is recursively pointing to the actual parent of
# the concat node.
#
# Then, when the concat node becomes 'ok', it yeilds to a callback set here
# that collapses the recursive node (stealing the one satsified child
# of the union the recursive node pointed to), and maybe sets up a new
# node (union? concat?) that itself will have a child that points to
# this concat node.
#
# The root union node should be none the wiser because it lost one
# satisfied child and gained another.
#
# For better or worse, in this manner the tree is built
# downward and to the left.
#

module Hipe
  module Parsie

    Stub = Object.new     # this is just used in temporary hacking
    class << Stub         # so we can get parse trees from fragmentary
      def ok?; false end  # parses.  ok to erase ?
      def done?; true end
    end

    CONCAT_INCREMENT = 1  # just to keep track of where we are using
    HARD_CODED_THIEVERY = 0 # ditto above

    # at one point this was called abstract
    # but we create an object of it below
    #
    class Reference
      include CommonInstanceMethods, Childable
      attr_reader :my_parse_id, :target_parse_id
      def initialize target_parse
        @target_parse_id = target_parse.parse_id
        @my_parse_id = Parses.register self
        @cached_decisions = {}
        # we use the above mainly because the look wip callback mechanism
        # doesn't happen in union.take just union.look
      end
      def is_reference?
        true
      end
      def target
        Parses[@target_parse_id]
      end

      # common things we may be defining redundanty b/c we don't want
      # to confuse ourselves with too many modules
      #
      def inspct ctxt, opts
        sprintf("#<Reference%s->%s>", @my_parse_id, @target_parse_id)
      end
      def inspct_tiny
        inspct nil, nil
      end
      def short
        "#<#{target.short}>"
      end
      def nil_parse?
        false
      end
      # end common things

      #
      # When a parse reference is no longer needed (when it is 'collapsed')
      # we leave a marker here for debugging.  If there are no other
      # references to the er reference this should in theory release it.
      #
      def to_tombstone! opts={}
        tombstone = Tombstone.build self, opts
        Parses.replace!(my_parse_id, tombstone)
        nil
      end

      #
      # replace a child with a tombstone.
      # @return removed child
      #
      def remove_child node, idx, opts={}
        no('no') unless node.children[idx]
        removed = node.children[idx]
        removed.unset_parent!
        tomb = Tombstone.build removed, opts
        node.children[idx] = tomb
        removed
      end


      #
      # put the new child in the spot,
      # make sure new_child doesn't already have a parent,
      # @return what was previously there (must be not nil)
      #
      def replace_child src_parent, src_idx, new_child
        old = src_parent.children[src_idx]
        no('no') unless old
        old.unset_parent!
        new_child.parent_id = src_parent.parse_id
        src_parent.children[src_idx] = new_child
        old
      end


      #
      # etc
      #
      def add_child parent_node, child
        no("clear child's existing parent first") if child.parent?
        no("really?") unless parent_node.kind_of?(UnionParse)
        child.parent_id = parent_node.parse_id
        parent_node.children << child
        new_idx = parent_node.children.length - 1
        new_idx
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

      def initialize target_parse
        super
        if ! target_parse.kind_of?(UnionParse)
          no("we need to develop this differently if we ever have "<<
             "recursive targets other than UnionParse. "<<
             "(#{target_parse.class.inspect})"
          )
        end
        class<<self; self end.send(:define_method, :root_union) do
          target_parse
        end
      end


      # common things we may be re-defining redundantly b/c we don't want
      # to mess with too many mixins here
      #
      def validate
        if (depth != parent.depth+1)
          no("#{short} has bad depth")
        end
        ui.puts "#{indent}ok (depth: #{depth})#{short}"
      end

      def ui # because we don't want to mess with parent-child
        @ui ||= target.ui
      end

      def ui_clear!
        @ui = nil
      end

      def inspct ctxt, opts
        sprintf("#<RecursiveReference%s->%s", @my_parse_id, @target_parse_id)
      end
      #
      # end common things


      def ins
        ui.puts "#{Inspecty::Indent*depth}#{short}"
      end

      # the parent should already said it (?) no reason to repeat
      def expecting; [] end

      #
      # There is some cruft in here b/c we used to think that we
      # had to trigger look wips all the time.  We do with recursive
      # references, but not vanilla references.
      #
      def look token
        if @cached_decisions[root_union.parse_context.tic]
          @cached_decisions[root_union.parse_context.tic].response
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
      # this is being called because you bounced out, because a concat
      # had a recursive reference.  At this point, the decision reflects
      # the state without taking recursive references into account
      #
      # now that you know what the union thinks without having calculated you
      # (the concat or its child recursive reference), you can ask the concat
      # what it would have said if it knew that child would give the respone
      # that the union has given.  (The recursive reference knows it can
      # steal the winning children from the root union to satisfy itself.)
      #
      def step_2_look_again union, frozen_decision, union_decision, idx, token
        my_parent_concat = self.parent
        no('no') unless self.root_union == union
        @cached_decisions[root_union.parse_context.tic] = frozen_decision

        concat_decision = my_parent_concat.look_decision token
        union_decision.add_response! concat_decision.response, idx

        if ! my_parent_concat.has_any_hook_once_when_becomes_ok
          size = frozen_decision.idxs_satisfied.size
          if size == 0
            # absolutely nothing!?
          elsif size == 1
            idx_in_union = frozen_decision.idxs_satisfied.last
            my_parent_concat.hook_once_when_becomes_ok do |*args|
              step3_when_ok self, idx_in_union, *args
            end
          else
            no("can't collapse recursive reference -- need exactly "<<
            "1 and had #{size} winning candidate nodes")
          end
        end
        nil
      end

      def take! foo
        @cached_decisions[root_union.parse_context.tic].response
      end

      def ridiculous_new_left_recursive_cparse cparse, new_ref
        cparse._start_offset = 0 + CONCAT_INCREMENT
          # todo we might wanna pass opts below
        cparse.build_current_children_and_evaluate!
        cparse.hook_once_when_becomes_ok do |cparse, decision, token|
          step3_when_ok new_ref, HARD_CODED_THIEVERY, cparse, decision, token
        end
        nil
      end


      #
      # this this is expected to be run at most once per concat object
      # (will cause bugs... @todo) when it goes from not ok to ok (if ever)
      # it 'collapses a reference' -- it pops the stolen child off of the root
      # union and puts it where the reference was
      #
      def step3_when_ok ref, idx_in_union, concat, decision, token
        # pop stolen off of root, pop onto concat where reference once was
        if ! ref.parent? || ref.parent != concat
          no('sukland')
        end
        stolen = remove_child root_union, idx_in_union, :signed_by => concat
        idx_in_concat = ref.index_in_parent
        refo = replace_child concat, idx_in_concat, stolen
        no('no') if refo.object_id != ref.object_id
        refo.parent_id = concat.parse_id
        refo.to_tombstone!
        root_union.prune!(:signed_by => concat)
        refo = nil

        # find all of the children for the union symbol that are left
        # recursive children, and add them to this union
        children_productions = root_union.production.children
        # we need to fake it so that the recursive hook is triggered
        root_union.production._building_this_parser = root_union
        idxs_added = []
        children_productions.each_with_index do |prod,idx|
          if ! prod.has_children? then next
          elsif left_recursive_concat_production?(prod)
            new_ref = nil
            cparse = prod.build_parse(
              root_union.parse_context,
              root_union,
              :recursive_hook => lambda do |_prod, _ctxt, _kls, _opts|
                new_ref = Reference.new _prod.building_this_parser
                new_ref
              end
            )
            new_ref.parent_id = cparse.parse_id # dangerous as all getout
            cparse.unset_parent! # dumb
            ridiculous_new_left_recursive_cparse cparse, new_ref
            idxs_added << add_child(root_union, cparse)
          else
            no("we have never dealt with this kind of grammar before")
          end
        end
        root_union.production._building_this_parser = nil
        root_union.hook_once_after_union_take! do |up, take_decision, token|
          # this makes some assumptions about the beginning state of
          # the new concat
          # just to get it in the running
          take_decision.idxs_open.concat(idxs_added)
        end
      end

      def left_recursive_concat_production? cp
        cp.kind_of?(ConcatProduction) &&
          cp.children[0].kind_of?(SymbolReference) &&
          cp.children[0].target_production.production_id ==
             root_union.production.production_id
      end
    end
  end
end
