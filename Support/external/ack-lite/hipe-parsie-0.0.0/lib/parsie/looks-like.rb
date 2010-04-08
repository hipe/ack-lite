module Hipe
  module Parsie
    module LooksLike
      #
      # dubious metaprogramming.
      # Let a class or a module define the types of objects it can
      # either construct with or enhance based on a set of methods
      # those objects must respond_to? and optionally a set of methods
      # that is must not respond_to?
      #
      # See test for examples.


      class << self
        def enhance mod
          thing = SpeechSituation.new(mod)
          yield(thing) if block_given?
          thing
        end
      end
      class Looker < Struct.new(:looks_like, :responds_to, :wont_override)
        include Lingual
        def initialize mod
          @mod = mod
        end
        %w(looks_like responds_to wont_override).each do |meth|
          define_method("#{meth}=") do |x|
            unless self.send(meth).nil?
              fail("#{const_basename(self.class)} for #{const_basename(@mod)} "<<
              "already has #{meth} set: #{send(meth).inspect}")
            end
            if %w(responds_to wont_override).include? meth
              if x.size == 1 && x[0].kind_of?(Array)
                x = x[0]
              end
            end
            super(x)
          end
        end
        def describe
          s = "to be a #{const_basename(@mod)} it must define " << oxford_comma(
          responds_to.map(&:to_s)) << '.'
          if wont_override && wont_override.any?
            s << " #{const_basename(@mod)} will not override " << oxford_comma(
            wont_override.map(&:to_s)) << '.'
          end
          s
        end
      end
      class SpeechSituation
        include Lingual
        def initialize(mod)
          @mod = mod
          @responds_to = @looks_like = @done = nil
          meta = class << mod; self end
          meta.send(:define_method, :singleton_class){meta}
          meta.send(:define_method, :define_method!){|name,&block|
            fail("no") if instance_methods.include?(name)
            define_method(name,&block)
          }
          class << meta
            def define_method! name, &block
              fail("no: #{name}") if instance_methods.include?(name)
              define_method(name, &block)
            end
          end
          looker = Looker.new(mod)
          block = proc{looker}
          mod.define_method!('looks',&block)
          mod.singleton_class.define_method!('looks',&block)
        end
        def if_responds_to? *if_responds_to
          fail("no") if @if_responds_to
          @if_responds_to = if_responds_to
          if @looks_like
            looks_like_if_responds_to?(@looks_like, if_responds_to)
          end
          self
        end
        alias_method :when_responds_to, :if_responds_to?
        def looks_like looks_like
          fail("no") if @looks_like
          @looks_like = looks_like
          if @if_responds_to
            looks_like_if_responds_to?(looks_like, @if_responds_to)
          end
          self
        end
        def wont_override(*meth)
          @mod.looks.wont_override = meth
          self
        end
        def looks_like_if_responds_to?(looks_like, responds_to)
          @mod.looks.looks_like = looks_like
          @mod.looks.responds_to = responds_to
          fail("no") if @done
          @done = true
          looks_like_meth = "looks_like_#{looks_like}?"
          doesnt_look_meth = "doesnt_look_like_#{looks_like}_because"
          couldnt_use_meth = "couldnt_use_it_because"
          @mod.singleton_class.define_method!(doesnt_look_meth){|mix|
            responds_to.select{|meth| ! mix.respond_to?(meth)}
          }
          @mod.singleton_class.define_method!(looks_like_meth){|mix|
            send(doesnt_look_meth,mix).empty?
          }
          @mod.singleton_class.define_method!(couldnt_use_meth){|mix|
            "it couldn't be used as a #{const_basename(me)} because "<<
            "it doesn't respond to " << oxford_comma(
              send(doesnt_look_meth,mix)
            )
          }
          self
        end
      end
    end
  end
end

