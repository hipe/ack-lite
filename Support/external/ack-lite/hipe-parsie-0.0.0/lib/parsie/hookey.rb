module Hipe
  module Parsie
    module Hookey
      #
      # A class that extends hookey gets a dsl to define any number of
      # 2 different kinds of hooks that clients can set and add to, and that
      # its objects will run at certain points in its lifetime.
      #
      # a 'hook once' is a queue of blocks
      # (usually just zero or one in practice) all of which are run
      # at a certain point in the object offerring the hook service.
      # After they are run once they are discarded.
      #
      # a 'single' is the same kind of thing, it is only run once,
      # but it is the only one that can occupy that slot.  An error
      # is thrown if the user tries to add more than one hook to that spot.
      # Once it is run once it is discarded.  The advantage of
      # only allowing one block per slot is that
      # the class offering the hook service can reliably get
      # a return value from the executed hook. (as opposed to dealing with
      # a list of zero or more returned values from a 'hook once' queue.)
      # This single form has become the defacto default as reflected
      # the the language below of generated methods.
      #
      # The fact that both of the above types of hooks are run once and
      # then discarded is just a safety measure.  If it were required,
      # a non-destructive hooking service could be offered.
      #
      # We make a little dsl for this not to be cute but to ensure
      # that we are setting the hooks we think we are setting and
      # running the hooks we think we are running.
      #

      include CommonInstanceMethods # no()

      class DefinedHooks
        attr_reader :onces, :singles
        def initialize
          @onces = Set.new
          @singles = {}
          class << @onces
            alias_method :has?, :include?
          end
          class << @singles
            alias_method :has?, :has_key?
          end
        end
      end

      class Hooks
        attr_reader :onces, :singles
        def initialize
          @onces = Hash.new{|h,k| h[k] = []}
          @singles = {}
          class << @singles
            alias_method :has?, :has_key?
          end
        end
      end

      def self.extended klass
        klass.send(:define_method, :hooks) do
          @hooks ||= Hooks.new
        end
      end

      def defined_hooks
        @definedhooks ||= DefinedHooks.new
      end

      def has_hook hook_name, opts={}
        set_name = opts[:set_hook_with] || "set_hook_#{hook_name}".to_sym
        has_name = "has_hook_#{hook_name}".to_sym
        pop_name = "pop_hook_#{hook_name}".to_sym
        no("won't redefine a hook") if defined_hooks.singles.has?(hook_name)
        defined_hooks.singles[hook_name] = true
        module_eval do
          define_method(has_name) do
            hooks.singles.has?(hook_name)
          end

          define_method(set_name) do |&block|
            no("no") unless block # will kill our each logic below
            if hooks.singles.has?(hook_name)
              no("#{hook_name} hook already occupying slot for this single hook")
            end
            hooks.singles[hook_name] = block
          end

          define_method(pop_name) do
            resp = hooks.singles.delete(hook_name)
            resp
          end
        end
      end

      def has_hook_once hook_name, opts={}
        add_name = opts[:set_hook_with] || "hook_once_#{hook_name}".to_sym
        has_name = "has_any_hook_once_#{hook_name}".to_sym
        run_name = "run_hook_onces_#{hook_name}".to_sym
        no("won't redefine a hook") if defined_hooks.onces.has?(hook_name)
        defined_hooks.onces.add(hook_name)
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
