module Hipe
  module Parsie
    module Hookey
      include CommonInstanceMethods # no()

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

      def has_hook_once hook_name, opts={}
        add_name = opts[:set_hook_with] || "hook_once_#{hook_name}".to_sym
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
  end
end
