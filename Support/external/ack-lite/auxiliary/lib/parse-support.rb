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
    end
    Debug.true = false
    Debug.look = false

    $p = Parses # shh

    class ParseContext
      @all = RegistryList.new
      class << self
        attr_reader :all
      end
      attr_reader :context_id
      def initialize
        @context_id = self.class.all.register(self)
        @token_locks = Hash.new do |h,k|
          h[k] = Setesque.new(k)
        end
      end
      def tic
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
      include Misc # no()
      def has_hook_once hook_name
        add_name = "hook_once_#{hook_name}".to_sym
        run_name = "run_hook_onces_#{hook_name}".to_sym
        @defined_hook_onces ||= {}
        no("won't redefine a hook") if @defined_hook_onces[hook_name]
        @defined_hook_onces[hook_name] = true
        module_eval do
          define_method(add_name) do |&block|
            no("no") unless block # will kill our each logic below
            @hook_onces ||= Hash.new{|h,k| h[k] = []}
            @hook_onces[hook_name] << block
          end

          define_method(run_name) do |&block|
            return -1 if @hook_onces.nil?
            num_ran = 0
            while (hook = @hook_onces[hook_name].shift)
              block.call hook
              num_ran += 1
            end
            num_ran
          end
        end
      end
    end

    module Inspecty
      def class_basename
        self.class.to_s.split('::').last
      end
      def insp; $stdout.puts inspct; 'done.' end
      def inspct_tiny
        sprintf("<%s%s#%s>",
          class_basename.scan(/[A-Z]/).join(''),
          symbol_name.inspect,
          @parse_id
        )
      end
      # block - true or false whether to skip
      def inspct_attr(ll,arr,ind='',&b)
        arr = [arr] unless arr.kind_of? Array
        arr.each do |a|
          val = instance_variable_get(a)
          next if block_given? && ! yield(val)
          ll << sprintf("#{ind}#{a}=%s",val.inspect)
        end
        nil
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
