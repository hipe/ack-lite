module Hipe
  module Parsie
    class Sexpesque < Array # thanks zenspider
      class << self
        def [](*a)
          new(*a)
        end
      end
      def initialize(*a)
        super(a)
      end
      def all name=nil
        select do |x|
          x.kind_of?(Sexpesque) &&  x[0] == name
        end
      end
      def [] sym
        return super(sym) if sym.kind_of?(Fixnum) || sym.kind_of?(Range)
        all = self.all(sym)
        case all.size
        when 0: nil
        when 1: all[0]
        else
          fail("had #{all.size} #{sym.inspect}. use all().")
        end
      end
      def unjoin
        if size != 3 then fail(
          "need three to unjoin had #{size} for #{self[0]}"
        ) end
        thing = Array.new([self[1], *self[2][1].all(self[1][0])])
        thing
      end
      def to_hash
        Hash[ self[1..-1].map do |x|
          val = x.size==2 ? x[1] : x[1..-1]
          if val.nil?
            nil
          else
            [x[0], val]
          end
        end.compact ]
      end
    end
  end
end
