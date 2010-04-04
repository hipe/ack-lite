module Hipe
  module Parsie
    OPEN      = 1 # == ! done?
    SATISFIED = 2 # == ok?
    WANTS     = 4
    Parses = RegistryList.new
    class << Parses
      alias_method :orig_register, :register
      def register(*args, &block)
        orig_register(*args, &block)
      end
    end

    RootParse = Object.new
    class << RootParse
      parse_id = Parses.register(RootParse)
      send(:define_method, :parse_id){ parse_id }
      def inspect
        sprintf('#<%s:%s>','RootParse', parse_id)
      end
      alias_method :short, :inspect
      def depth; 0 end
    end

    Contexts = RegistryList.new

    Debug = Object.new
    class << Debug
      def true?; @true end
      def true= val; @true = val end
      def look?; @looks end
      def look= val; @looks = val end
      def all= val
        self.look = val
        self.true = val
      end
      def out= mixed
        @out = mixed
      end
      def out
        @out ||= $stderr
      end
      def puts *a
        out.puts *a
      end
    end
    Debug.true = false
    Debug.look = false

    $p = Parses # shh

    #
    # a class that includes this must define
    #   'open' 'satisfied' 'wants'
    #
    # if it doesn't already have them, it will get:
    #   open? satisfied? wants? ok[?] done[?]
    #   and setters and crap
    #
    # this whole thing is begging for a refactor app wide @todo
    #
    module Decisioney
      include Misc # children usually want desc_bool?
      @meta = {
        :main_three  => [:wants, :satisfied, :open],
        :alt_two     => [:ok, :done],
        :equivalents => [[:satisfied, :ok]],
        :inverted_equivalents => [[:open, :done]]
      }
      @meta[:all_five] = @meta[:main_three] + @meta[:alt_two]
      class << self
        attr_reader :meta

        def aliaz_method klass, nu, old
          if klass.method_defined?(old) && ! klass.method_defined?(nu)
            klass.send(:alias_method, nu, old)
          end
        end

        def dufine_method a, b, &c
          unless a.method_defined? b
            a.send(:define_method, b, &c)
          end
        end

        def included klass

          # make aliases for getters and setters only when ..
          meta[:equivalents].each do |(get1, get2)|
            set1, set2 = "#{get1}=", "#{get2}="
            aliaz_method klass, set2, set1
            aliaz_method klass, get2, get1
          end

          # ridiculous inverted crap
          meta[:inverted_equivalents].each do |(get1, get2)|
            set1, set2 = "#{get1}=", "#{get2}="
            dufine_method(klass, get2){ ! send(get1) }
            dufine_method(klass, set2){ |bool| send(set1, !bool) }
          end

          meta[:all_five].each do |fug|
            question_form = "#{fug}?"
            unless klass.method_defined? question_form
              klass.send :alias_method, question_form, fug
            end
          end
        end
      end

      def complete?
        complete_failure.nil?
      end

      def complete_failure
        not_bool = []
        Decisioney.meta[:main_three].each do |meth|
          resp = send(meth)
          unless bool?(resp)
            not_bool.push [meth, resp]
          end
        end
        not_bool.any? ? not_bool : nil
      end

      def assert_complete
        unless complete?
          no("decision not complete: #{complete_failure.inspect}")
        end
      end

      def response
        want_bit = wants? ? WANTS : 0
        ok_bit   = ok?    ? SATISFIED : 0
        open_bit = done?  ? 0 : OPEN
        want_bit | ok_bit | open_bit
      end

      def equivalent? other
        diff(other).empty?
      end

      def diff other
        response = {}
        Decisioney.meta[:main_three].each do |item|
          left_val, right_val = send(item), other.send(item)
          if left_val != right_val
            response[item] = [left_val, right_val]
          end
        end
        response
      end

      def inspct_for_debugging
        sprintf('%s%s',
          wants? ? '___WANTS___' : '_ ',
          short
        )
      end
    end

    class Response < Struct.new(:wants, :satisfied, :open)
      include Decisioney
      def self.[] int
        No.no("need Fixnum had #{int.class}") unless int.kind_of?(Fixnum)
        self.new(
          0 != WANTS & int,
          0 != SATISFIED & int,
          0 != OPEN & int
        )
      end
      protected :initialize
    end


    class ParseContext
      include Misc
      @all = RegistryList.new
      class << self
        attr_reader :all
      end
      attr_reader :context_id, :tic
      def initialize
        @tic = 0
        @context_id = self.class.all.register(self)
        @token_locks = Hash.new do |h,k|
          h[k] = Setesque.new(k)
        end
        @pushbacks = []
      end
      def tic!
        @tic += 1
        @token_locks.each{|(k,arr)| arr.clear }
        # @pushbacks.clear
      end
      def pushback obj
        if @pushbacks.size > 0
          no("for now can't take more than one pushback per tic")
        end
        @pushbacks.push obj
      end
      def pushback_pop
        @pushbacks.pop
      end
      def pushback?
        @pushbacks.size > 0
      end
    end

    module FaileyMcFailerson
      def fail= parse_fail
        no("type assert fail") unless parse_fail.kind_of? ParseFail
        @last_fail = parse_fail
      end
      def fail
        @last_fail
      end
      def failed?
        ! @last_fail.nil?
      end
    end

    module StrictOkAndDone
      def done?
        no("asking done when done is nil") if @done.nil?
        @done
      end
      def open?
        ! done?
      end
      def ok?
        no("asking ok when ok is nil") if @ok.nil?
        @ok
      end
    end

    module Hookey
      include Misc # no()

      class DefinedHooks
        attr_reader :onces
        def initialize
          @onces = Set.new
          class << @onces
            alias_method :has?, :include?
          end
        end
      end
      class Hooks
        attr_reader :onces
        def initialize
          @onces = Hash.new{|h,k| h[k] = []}
        end
      end

      def self.extended klass
        klass.send(:define_method, :hooks) do
          @hooks ||= Hooks.new
        end
      end

      def has_hook_once hook_name
        add_name = "hook_once_#{hook_name}".to_sym
        has_name = "has_any_hook_once_#{hook_name}".to_sym
        run_name = "run_hook_onces_#{hook_name}".to_sym
        @defined_hooks ||= DefinedHooks.new
        no("won't redefine a hook") if @defined_hooks.onces.has?(hook_name)
        @defined_hooks.onces.add(hook_name)
        module_eval do
          define_method(has_name) do
            hooks.onces[hook_name].any?
          end

          define_method(add_name) do |&block|
            no("no") unless block # will kill our each logic below
            hooks.onces[hook_name] << block
          end

          define_method(run_name) do |&block|
            return -1 unless hooks.onces.has_key?(hook_name)
            num_ran = 0
            while (hook = hooks.onces[hook_name].shift)
              block.call hook
              num_ran += 1
            end
            num_ran
          end
        end
      end
    end


    # a bunch of strictness
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
      def depth= x
        @depth = x
      end
      def indent; '  '*depth end
      def index_in_parent
        parent.index_of_child self
      end
    end

    #
    # we were avoiding this for some reason but ...
    #
    module Parsey
      include Misc # 'no'
      def parse_context
        ParseContext.all[@context_id]
      end
      def tic
        parse_context.tic
      end
    end

    module BubbleUppable
      def bubble_up obj
        if ! obj.kind_of? PushBack
          No.no('no for now')
        end
        if ! parent?
          No.no('for now all parses have parent except root parse')
        end
        if parent == RootParse
          parse_context.pushback obj
        else
          if parent.respond_to? :bubble_up
            parent.bubble_up obj
          else
            No.no("how come parent no have bubble_up?")
          end
        end
      end
    end

    #
    # Tombstones need not be permanant.  They are just strings that
    # can be used in debugging to show where an object once was
    # and possibly to describe where it went
    #
    class Tombstone < String;
      def self.build parse, opts={}
        if opts[:signed_by]
          rm = ""
          by = opts[:signed_by].short
          by = " removed by #{by}"
        else
          rm = "removed "
          by = ""
        end
        removed_thing = parse.short
        str = "tombstone: #{rm}#{removed_thing}#{by}"
        Tombstone.new str
      end
    end

    class ParseTree < Struct.new(
      :type, :symbol_name, :production_id, :value
    )
      def inspct ctx=InspectContext.new,opts={};
        l = []
        ind = ctx.indent.dup
        ctx.indent_indent!
        l << sprintf(
          "#<ParseTree tp:%s nm:%s prod:%s chldrn:",
          type,symbol_name,production_id
        )
        if value.kind_of? ParseTree
          l << value.inspct(ctx,opts)
        else
          l << value.inspect
        end
        l.last << ">"
        s = l.join(" ")
        if s.length < 80
          return s
        else
          return l * "\n   #{ind}"
        end
      end
    end # ParseTree
  end # Parsie
end # Hipe