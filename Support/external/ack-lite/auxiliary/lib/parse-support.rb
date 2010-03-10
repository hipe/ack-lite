module Hipe
  module Parsie
    OPEN      = 1 # == ! done?
    SATISFIED = 2 # == ok?
    WANTS     = 4
    Parses = RegistryList.new
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
    end
    Debug.true = false
    Debug.look = false

    $p = Parses # shh

    class ParseContext
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
      end
      def tic!
        @tic += 1
        @token_locks.each{|(k,arr)| arr.clear }
      end
    end

    module Decisioney
      def insp
        puts inspct_tiny
        'done.'
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

      include Misc # no()
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
      def unset_parent!
        no('no parent to clear. check parent? first') unless @parent_id
        @parent_id = nil
      end
      def parent?
        ! @parent_id.nil?
      end
      def parent_id= pid
        no("no") unless pid
        no("unset parent first") if @parent_id
        @parent_id = pid
      end
      def parent
        no("check parent? first") unless @parent_id
        Parses[@parent_id]
      end
      def index_in_parent
        parent.index_of_child self
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
          by = opts[:signed_by].inspct_tiny
          by = " removed by #{by}"
        else
          rm = "removed "
          by = ""
        end
        removed_thing = parse.inspct_tiny
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
    end
  end
end
