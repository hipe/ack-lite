root = File.dirname(__FILE__)
require root + '/nonterminal-inspecty.rb'
# others included at end

module Hipe
  module Parsie

    # for parsers - nonterminals

    module NonterminalParsey

      # note11: parentable must trump childable so include parent after child
      # (before in the list!)
      # http://gnuu.org/2010/03/25/fixing-rubys-inheritance-model/
      #
      include NonterminalInspecty, BubbleUppable, Parentable, Childable, Parsey

      attr_accessor :last_look
      def production
        Productions[@production_id]
      end
      def symbol_name
        production.symbol_name
      end
      def symbol_name_for_debugging
        use = symbol_name
        if (use == false || use == nil)
          if (!parent?)
            use = "(anonymous with no parent!!??)"
          else
            parent_name = parent.symbol_name_for_debugging
            use = "(#{parse_type} in #{parent_name})"
          end
        end
        use
      end
      def nil_parse?
        false
      end
      def is_reference?
        false
      end
      def unparse
        _unparse(rslt = [])
        rslt
      end
      def locks_init
        @lock = {
          :ok?   => false,
          :done? => false,
          :look  => false,
          :take! => false
        }
      end
      def looking?; @lock[:look] end
      def doneing?; @lock[:done?] end
      def oking?;   @lock[:ok?] end
      def look_lockout &block
        if done?
          no("\n\n\nWON'T LOOK WHEN DONE--CHECK IT OUT\n\n")
        end
        common_lockout :look, &block
      end
      def take_lockout &block
        no("can't take when done") if done?
        common_lockout :take!, &block
      end
      def done_lockout &block
        common_lockout :done?, &block
      end
      def ok_lockout &block
        common_lockout :ok?, &block
      end
      def common_lockout type, &block
        wip_name = "wip_#{type}".to_sym # :wip_ok? :wip_done? :wip_look
        throw wip_name, {:pid=>parse_id} if @lock[type]
        @lock[type] = true
        wip = catch(wip_name) do
          yield
          # a 'wip' means a work in progress, when a 'wip' is thrown
          # it means a recursive node is trying to visit itself.
          # this may throw from self as child, depending on how we
          # choose to implement this.  In the client code (i.e. anywhwere
          # other than here) client should catch wips originating
          # from self (or target) and take appropriate measures.  Here we
          # catch all wips and rethrow them to bubble them up.  If we catch a
          # wip that originated (by necessity) somewhere below us but did not
          # originate from us, we unlock our own lock first so we are not
          # locked out later
          nil
        end
        if wip
          @lock[type] = false if (wip && wip[:pid]!=parse_id)
          throw wip_name, wip
        end
        @lock[type] = false
        nil
      end
      def can_have_children?
        true
      end
      def index_of_child child
        found = false
        @children.each_with_index do |c,i|
          if c == child
            found = i
            break;
          end
        end
        no("child not found") unless found
        found
      end
    end # end NonterminalParsey
  end
end

require root + '/union-parse.rb'
require root + '/concat-parse.rb'
require root + '/range-parse.rb'
