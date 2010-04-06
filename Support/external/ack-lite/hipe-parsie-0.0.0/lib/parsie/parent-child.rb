module Hipe
  module Parsie
    # per :note11 parent methods trump child methods
    module Parentable
      def can_have_children?
        true
      end
      # will be overridden when necesary
      def each_existing_child &block
        children.each_with_index do |child, idx|
          if child.is_nil_parse? then no(
            "NilParse found in call do each_existing_child(). "<<
            "fix this for #{short}"
          ) end
          block.call(child, idx)
        end
        nil
      end
      def each_child &block
        children.each_with_index do |child, idx|
          block.call(child, idx)
        end
        nil
      end
      def index_of_child_assert child
        found = false
        each_existing_child do |c,i|
          if c == child
            found = i
            break;
          end
        end
        unless found
          no("this is no child of mine #{child.short} (parent is #{self.short})")
        end
        found
      end
      def num_children
        children.size
      end
      def cascade &block
        block.call(self)
        cascade_to_children(&block)
      end
      def ins foo=nil
        ui_push(foo) if foo
        num = num_children
        num = (num==0) ? '(0)' : "(#{num}):"
        ui.puts "#{indent}#{short}#{num}"
        each_child do |child, idx|
          if child.is_nil_parse?
            ui.puts "#{Inspecty::Indent * (depth + 1)}#{child.short}"
          else
            child.ins
          end
        end
        if foo
          ret = ui_pop
        else
          ret = nil
        end
        ret
      end
      def validate_down
        num = 0
        each_existing_child do |child, idx|
          if child.parent != self
            fuck = <<-HERE.gsub(/^ */,'')
            failed totally at life.
            i am #{short}, i have a child #{child.short} at index #{idx}
            who thinks his parent is #{child.parent.short}.
            How did this happen you dumb fuck.
            HERE
            no(fuck)
          else
            num += 1
          end
          child.validate_down
        end
        ui.puts "#{indent}ok down (num children: #{num})#{short}"
      end
      # implementing class can override this, sure, but still call validate children!

    private
      def cascade_to_children &block
        each_existing_child do |c, idx|
          c.cascade(&block)
        end
        nil
      end
      def ui_push foo
        cascade_to_children{ |x| x.ui_clear! }
        @uis ||= []
        @uis.push(@ui)
        @ui = foo
        nil
      end
      def ui_pop(do_string_io = true)
        cascade_to_children{ |x| x.ui_clear! }
        ret = @ui
        @ui = @uis.pop
        if ret.kind_of?(StringIO)
          ret.rewind
          ret = ret.read
        end
        ret
      end
    end

    # a bunch of strictness
    module Childable
      def parent_id
        unless @parent_id
          no("no parent_id. check parent? first in #{short}")
        end
        @parent_id
      end
      def parent
        unless @parent_id
          no("no parent_id. check parent? first in #{short}")
        end
        Parses[@parent_id]
      end
      def parent_clear!
        no('no parent to clear. check parent? first') unless @parent_id
        @parent_id = nil
      end
      def parent?
        ! @parent_id.nil?
      end
      def parent_id= pid
        no("no") unless pid
        no("parent already set.  unset parent first.") if @parent_id
        @parent_id = pid
        parent = Parses[pid]
        if parent.depth.nil?
          no("to be a parent, you need depth")
        end
        @depth = parent.depth + 1
      end
      def depth
        @depth
      end
      def ui # the ui that most parse objects use
        @ui ||= parent.ui
      end
      def ui_clear!
        @ui = nil
      end
      def indent
        Inspecty.indent * depth
      end
      def depth= x
        @depth = x
      end
      def indent; '  '*depth end
      def index_in_parent_assert
        parent.index_of_child_assert self
      end
      def cascade &block
        block.call(self)
      end
      # there is a hole here in that it assumes all childable are parentable
      # but we want to leave it as it in instead of including childable
      # in parentable
      #
      def validate_up
        index_in_parent_assert
        parent.validate_up
        ui.puts "#{indent}ok child is in parent (#{short} in #{parent.short})"
      end
    end
    module ParentableAndChildable
      # note11: parentable must trump childable so include parent after child
      # (before in the list!)
      # http://gnuu.org/2010/03/25/fixing-rubys-inheritance-model/
      #
      include Parentable, Childable

      # this is only a starting point this must not be called by
      # other validate functions
      #
      def validate_around
        validate_down
        validate_up
      end
    end
  end
end
