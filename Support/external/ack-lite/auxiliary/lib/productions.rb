module Hipe
  module Parsie
    Productions = RegistryList.new
    $pr = Productions # sh

    # universal production mixings

    module Productive
      include Misc
      def symbol_name= name;
        Productive.make_getter(self,:symbol_name,name)
      end
      def production_id= production_id
        Productive.make_getter(self,:production_id,production_id)
      end
      def table_name= foo
        Productive.make_getter(self,:table_name,foo)
      end
      def self.make_getter(obj,meth,val)
        no("don't clobber this") if obj.respond_to? meth
        class<<obj; self end.send(:define_method,meth){val}
      end
    end

    class StringProduction
      include Productive
      attr_accessor :string_literal
      def initialize string
        unless string.kind_of? String
          raise ParseParseFail.new(
            "string must be string not #{string.inspect}"
          )
          # note we let empty strings thru as a valid token
        end
        @string_literal = string
      end
      def build_parse ctxt
        StringParse.new(self)
      end
      def to_bnf_rhs; @string_literal.inspect end
      def zero_width?; @string_literal == "" end
    end

    class RegexpProduction
      include Productive
      attr_accessor :re
      def initialize re; @re = re end
      def build_parse ctxt
        RegexpParse.new(self)
      end
      # @todo not bnf!
      def to_bnf_rhs;
        @re.inspect
      end
      def zero_width?; !! (@re =~ "") end
    end

    class SymbolReference
      include Productive
      attr_reader :target_symbol_name
      def initialize symbol_name
        @target_symbol_name = symbol_name
      end
      def target_production
        unless Cfg.all[table_name].symbols.has?(target_symbol_name)
          no("#{target_symbol_name.inspect} not yet defined for "<<
          " \"#{table_name}\"")
        end
        prod = Cfg.all[table_name].symbol(target_symbol_name)
        prod
      end
      def reference_check
        unless Cfg.all[table_name].symbols.has?(target_symbol_name)
          throw :ref_fail, {:name=>target_symbol_name}
        end
      end
      def build_parse ctxt
        prod = target_production
        prod.build_parse ctxt
      end
      # we are going to let the implementors handle recursion
      def zero_width?
        target_production.zero_width?
      end
      def to_bnf_rhs; @target_symbol_name.to_s end
    end


    # nonterminal productions & support

    module NonterminallyProductive
      # this is concerned with setting locks so
      # recursive symbols don't try to build themselves infinitely
      def nonterminal_common_init_locks
        @making_this_parser = nil
      end
      def nonterminal_common_build_parse ctxt, parse_class
        if @making_this_parser
          rslt = ParseReference.new @making_this_parser
        else
          parser = parse_class.new self, ctxt #note2
          @making_this_parser = parser
          parser.build_children!
          @making_this_parser = nil
          rslt = parser
        end
      end
    end

    class UnionSymbol
      include Productive, NonterminallyProductive
      attr_accessor :children
      def initialize sym
        @zero_width = nil
        nonterminal_common_init_locks
        @children = AryExt[[sym]]
      end
      def add child
        @zero_width = nil
        no("children of a union must "<<
        "have the same name: #{symbol_name.inspect}, "<<
        "#{child.symbol_name.inspect}") unless
          symbol_name == child.symbol_name
        @children.push child
        nil
      end
      def build_parse ctxt
        nonterminal_common_build_parse ctxt, UnionParse
      end
      # this probably isn't correct
      def zero_width?
        return @zero_width unless @zero_width.nil?
        throw :wip_zero_width?,{:prod_id=>production_id} if @zero_width_lock
        @zero_width_lock = true
        zero_width = false
        @children.each do |child|
          child_answer = nil
          wip = catch(:wip_zero_width?) do
            child_answer = child.zero_width?
            nil
          end
          if wip
            throw wip if (wip[:prod_id] != production_id)
            next # we just skip them? this can't be right
          else
            if child_answer
              zero_width = true
              break
            end
          end
        end
        @zero_width_lock = false
        @zero_width = zero_width
      end
      # doesn't need reference_check as long as note1
    end

    class ConcatProduction
      include Productive, NonterminallyProductive
      attr_accessor :children
      def initialize grammar, ary
        nonterminal_common_init_locks
        @children = ary.map do |x|
          prod = grammar.build_production(x,[String, Symbol])
          prod.table_name = grammar.table_name
          # as they are only strings or symbol references, they don't
          # need to register with the table and get production ids, etc
          prod
        end
        AryExt[@children]
        @final_offset = nil
        @satisfied_offset = nil
      end
      def build_parse ctxt
        nonterminal_common_build_parse ctxt, ConcatParse
      end
      def determine_offsets!
        @final_offset = @children.length - 1;
        # find the first offset that is not zero width starting from end
        idx = (0..@final_offset).map.reverse.detect do |i|
          !@children[i].zero_width?
        end
        idx ||= -1
        @satisfied_offset = idx
      end
      def final_offset
        determine_offsets! if @final_offset.nil?
        @final_offset
      end
      def satisfied_offset
        determine_offsets! if @satisfied_offset.nil?
        @satisfied_offset
      end
      def reference_check
        missing = []
        @children.select{|p| p.kind_of? SymbolReference}.each do |p|
          if (fail = catch(:ref_fail){ p.reference_check; nil })
            missing << fail[:name]
          end
        end
        throw :ref_fail, {:names => missing } if missing.length > 0
      end
      def to_bnf_rhs; @children.map(&:to_bnf_rhs) * ' ' end
    end
  end
end

