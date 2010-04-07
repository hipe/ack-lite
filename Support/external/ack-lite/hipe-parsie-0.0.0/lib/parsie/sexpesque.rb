module Hipe
  module Parsie
    class Sexpesque < Array
      class << self
        def [](*a)
          new(*a)
        end
      end
      def initialize(*a)
        super(a)
      end
    end
  end
end
