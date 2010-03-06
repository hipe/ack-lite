root = File.dirname(__FILE__)
require root + '/nonterminal-inspecty.rb'
# others included at end

module Hipe
  module Parsie

    # for parsers - nonterminals

    module NonterminalParsey
      include Misc
      def production
        Productions[@production_id]
      end
      def parse_context
        ParseContext.all[@context_id]
      end
      def symbol_name
        production.symbol_name
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
        no("#{inspct_tiny} can't look when done") if done?
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
        types =
        wip_name = "wip_#{type}".to_sym # :wip_ok? :wip_done? :wip_look
        throw wip_name, {:pid=>parse_id} if @lock[type]
        @lock[type] = true
        wip = catch(wip_name) do
          yield # this may throw from self as child, depending on how we
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
          throw wip
        end
        @lock[type] = false
        nil
      end
    end
  end
end

require root + '/union-parse.rb'
require root + '/concat-parse.rb'