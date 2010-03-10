module Hipe
  module Parsie
    Productions = RegistryList.new
    $pr = Productions # sh

    # universal production mixings

    #
    # Heapy is a dumb experimental thing because we don't want to see our
    # list of total parser objects (that are or ever were) get long for
    # whatever dumb reason.  When a parse is done being used (usually because
    # it is out of the running and not ok, b/c ok parses are usually kept
    # till the end), it is 'reset' and 'released'.  'reset' usually means
    # 1) recursively reset the children, 2) set internal counters back to
    # their beginning state.  'release' means simply that in theory there
    # are no nodes holding on to this node, and it is available in the 'heap'
    # of ready, blank parsers.  No attempts are made at checking references,
    # tho, so this is sure to cause bugs.
    #
    # The 'heap' of available blank parses stores them per production id
    # or with the key :default for the parses that don't (inline strings)
    #
    class Heap < Hash
      @all = {}
      class << self
        attr_reader :all
        def insp; puts inspct end
        def inspct
          ic = InspectContext.new
          ic.indent = '     '
          s = "#<Heap(all):"
          all.each do |(k,v)|
            s2 = "#{Inspecty.class_basename(k)}=>#{v.inspct(ic)}"
            s2.gsub!(/\n */,"") if (s2.length < 80)
            s << "\n  #{s2}"
          end
          s << ">"
          s
        end
      end
      def inspct ic
        s = sprintf("\n    #<Heap<-%s{", Inspecty.class_basename(@class))
        each do |(k,v)|
          s << "\n      #{k.inspect}=>["
          v.each_with_index do |x,k|
            s << v.inspct(ic)
          end
          s << "]"
        end
        s << "}>"
      end
      def initialize klass
        @class = klass
        self.class.all[klass] = self
        super(){|h,k| h[k] = AryExt[Array.new(0)] }
      end
    end
    module Heapy
      module InstanceMethods
        def release parse
          identifier = parse.production.production_id
          self.class.heap[identifier].push parse
        end
      end

      def self.extended klass
        return if klass.respond_to? :heap
        klass.send(:include, InstanceMethods)
        class << klass
          attr_accessor :heap
        end
        klass.heap = Heap.new(klass)
      end
    end

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
      def building_this_parser; nil end
      def really_stupid_heapy_terminal_parse_build klass
        if self.class.heap[:default].any?
          use_this_one = self.class.heap[:default].pop
          use_this_onse.send(:initialize, self)
        else
          rslt = klass.new self
        end
        rslt
      end
    end

    class StringProduction
      include Productive
      extend Heapy
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
      def build_parse ctxt, opts=nil
        really_stupid_heapy_terminal_parse_build StringParse
      end
      def to_bnf_rhs; @string_literal.inspect end
      def zero_width?; @string_literal == "" end
      def has_children?; false end
    end

    class RegexpProduction
      include Productive
      extend Heapy
      attr_accessor :re
      def initialize re; @re = re end
      def build_parse ctxt, opts=nil
        really_stupid_heapy_terminal_parse_build RegexpParse
      end
      # @todo not bnf!
      def to_bnf_rhs;
        @re.inspect
      end
      def zero_width?; !! (@re =~ "") end
      def has_children?; false end
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
      def build_parse ctxt, opts={}
        prod = target_production
        prod.build_parse ctxt, opts
      end
      # we are going to let the implementors handle recursion
      def zero_width?
        target_production.zero_width?
      end
      def has_children?
        target_production.has_children?
      end
      def to_bnf_rhs; @target_symbol_name.to_s end
    end


    # nonterminal productions & support

    module NonterminallyProductive
      # this is concerned with setting locks so
      # recursive symbols don't try to build themselves infinitely
      def nonterminal_common_init_locks
        @building_this_parser = nil
      end
      def building_this_parser
        @building_this_parser
      end
      # only for hackery
      def _building_this_parser= foo
        @building_this_parser = foo
      end
      def nonterminal_common_build_parse ctxt, parse_class, opts = {}
        if @building_this_parser
          if opts[:recursive_hook]
            rslt = opts[:recursive_hook].call(
              self, ctxt, parse_class, opts
            )
          else
            rslt = RecursiveReference.new @building_this_parser
          end
        else
          parser = parse_class.new self, ctxt #note2
          @building_this_parser = parser
          parser.build_children! opts
          @building_this_parser = nil
          rslt = parser
        end
        rslt
      end
      def has_children?; true end
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

      #
      # opts: :child_hook, :recursive_hook
      #
      def build_parse ctxt, opts={}
        nonterminal_common_build_parse ctxt, UnionParse, opts
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
      extend Heapy # release
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
        @final_offset = @zero_width_map = @satisfied_offset =
          @zero_width = nil
      end
      def zero_width_map
        determine_offsets! if @zero_width_map.nil?
        @zero_width_map
      end
      def zero_width?
        determine_offsets! if @zero_width.nil?
        @zero_width
      end
      def build_parse ctxt, opts={}
        nonterminal_common_build_parse ctxt, ConcatParse, opts
      end
      def determine_offsets!
        @zero_width_map = @children.map(&:zero_width?)
        @zero_width = ! @zero_width_map.detect{|x| x == false}
        @final_offset = @children.length - 1;
        # find the first offset that is not zero width starting from end
        idx = (0..@final_offset).map.reverse.detect do |i|
          false==@zero_width_map[i]
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
      def release_this_resetted_parse parse
        release parse
      end
    end
  end
end

