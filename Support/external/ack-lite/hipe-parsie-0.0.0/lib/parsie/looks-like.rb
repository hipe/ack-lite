module Hipe
  module Parsie
    module LooksLike
      #
      # Lazy interface inference. (dubious metaprogramming?)
      #
      # Let a class or a module define the types of objects it can
      # either construct with or enhance based on a set of methods
      # those objects must respond_to? and optionally a set of methods
      # that is must not respond_to?
      #
      # See test for examples.
      #
      # You might think that this is dumb and overkill but the fact
      # is that StringIO 'looks like' an IO but is not a kind_of? IO
      # so we end up with this pattern of lists of methods we need
      # to check for for things.  Without something like this there
      # is a lot of repetition in code for checking this stuff.
      #
      # depends: Lingual(const_basename), MetaTools
      #

      class << self
        def enhance mod
          voice = SpeechSituation.new(mod)
          if block_given?
            yield(voice)
            mod.looks.validate
          end
          voice
        end
      end

      class Look
        #
        # a "look" is a lazy interface (a list of method names)
        # and possibly a list of methods the thing won't override.
        #
        include Lingual

        def initialize mod
          @module = mod
          @responds_to = @name = @wont_override = nil
          @infected = false
        end

        attr_accessor :module, :infected
        alias_method :infected?, :infected

        def name
          @name
        end

        def name= foo
          fail("won't clobber name") unless @name.nil?
          fail("let's stick with symbols") unless foo.kind_of?(::Symbol)
          @name = foo
        end

        def shortname
          const_basename(self.module.to_s)
        end

        def methods_missing(mix)
          responds_to.select{|meth| ! mix.respond_to?(meth)}
        end

        def methods_blacklist(mix)
          wont_override.select{|meth| mix.respond_to?(meth)}
        end

        def ok?(mix)
          methods_missing(mix).empty? && methods_blacklist(mix).empty?
        end

        def not_ok_because(mix)
          ss = []
          if (bad = methods_missing(mix).map(&:to_s)).any?
            ss.push( "it doesn't respond to " << oxford_comma(bad,' or ') )
          end
          if (bad = methods_blacklist(mix).map(&:to_s)).any?
            ss.push( "it already responds to " << oxford_comma(bad) )
          end
          if ss.any?
            ss = [oxford_comma(ss)]
            ss.unshift "it couldn't be used as a #{shortname} because"
          end
          ss.join(' ')
        end

        # create strict setters and lazy getters for the two properties
        %w(wont_override responds_to).each do |meth|
          define_method(meth) do
            if instance_variable_get("@#{meth}").nil?
              instance_variable_set("@#{meth}",[])
            end
            instance_variable_get "@#{meth}"
          end
          define_method("#{meth}=") do |foo|
            # responds_to %w(foo bar)  instead of responds_to *%w(foo bar)
            if foo.kind_of?(Array) && foo.size == 1 && foo[0].kind_of?(Array)
              foo = foo[0]
            end
            unless send(meth).empty?
              fail("won't clobber @#{meth}")
            end
            fail("must be array, not #{foo.inspect}") unless
              foo.kind_of?(Array)
            if (bad = foo.map(&:class) - [String, Symbol]).any?
              fail("bad types for array for #{meth}=: "<<
                bad.map(&:to_s).map(&:inspect).join(', ')
              )
            end
            instance_variable_set("@#{meth}", foo)
          end
        end

        def valid?
          ! name.nil? && responds_to.any?
        end

        def validate
          fail("a look must have one or more methods") unless
            responds_to.any?
          fail("a look must have a name") if name.nil?
        end

        def infect
          fail("won't infect twice") if infected?
          fail("won't infect until valid") unless valid?

          looks_like_meth = "looks_like_#{name}?"
          couldnt_meth    = "doesnt_look_like_#{name}_because"

          self.module.singleton_class.define_method!(looks_like_meth) do |mix|
            looks.ok?(mix)
          end

          self.module.singleton_class.define_method!(couldnt_meth) do |mix|
            looks.not_ok_because(mix)
          end

          @infected = true
          nil
        end

        def describe
          s = "to be a #{shortname} it must define "<<
           oxford_comma(responds_to.map(&:to_s)) << '.'
          if wont_override && wont_override.any?
            s << " #{shortname} will not override " <<
             oxford_comma(wont_override.map(&:to_s)) << '.'
          end
          s
        end
      end

      class SpeechSituation
        #
        # This this is totally internal to this lib.  @api private
        # it is the one that actually does the doing when you call
        # LooksLike.enhance().  an object of it gets returned from that call,
        # and yielded to any block used in that call.
        #
        # This object does not persist.  It is only around during this
        # few lines of code during the definition phase.
        #

        def initialize(mod)
          look = Look.new(MetaTools[mod])
          @look = look
          block = proc{look}
          mod.singleton_class.define_method!(:looks, &block)
          nil
        end

      private
        attr_accessor :look
      public

        def if_responds_to? *meths
          look.responds_to = meths
          if look.valid? && ! look.infected?
            look.infect
          end
          self
        end
        alias_method :when_responds_to, :if_responds_to?

        def looks_like looks_like
          look.name = looks_like
          if look.valid? && ! look.infected?
            look.infect
          end
          self
        end

        def wont_override(*meth)
          look.wont_override = meth
          self
        end
      end
    end
  end
end

