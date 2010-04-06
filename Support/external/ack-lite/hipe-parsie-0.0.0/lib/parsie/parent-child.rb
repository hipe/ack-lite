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
          block.call(child, idx)
        end
        nil
      end
      def num_children
        children.size
      end
      def cascade &block
        block.call(self)
        each_existing_child do |c, idx|
          c.cascade(&block)
        end
        nil
      end
      def ins
        num = num_children
        num = (num==0) ? '(0)' : "(#{num}):"
        ui.puts "#{Inspecty::Indent*depth}#{short}#{num}"
        children.each do |child|
          if child.nil_parse?
            ui.puts "#{Inspecty::Indent*(depth+1)}#{child.short}"
          else
            child.ins
          end
        end
        nil
      end
      def validate_children
        num = 0
        each_existing_child do |child, idx|
          if child.kind_of?(Childable)
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
            child.validate
          end
        end
        ui.puts "#{indent}ok (num children: #{num})#{short}"
      end
      # implementing class can override this, sure, but still call validate children!
      alias_method :validate, :validate_children
    end

    # a bunch of strictness
    # avoid making a validate() here to avoid confusion
    module Childable
      def parent_id
        no("no parent_id. check parent? first") unless @parent_id
        @parent_id
      end
      def parent
        no("no parent_id. check parent? first") unless @parent_id
        Parses[@parent_id]
      end
      def unset_parent!
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
      def index_in_parent
        parent.index_of_child self
      end
      def cascade &block
        block.call(self)
      end
    end
  end
end
