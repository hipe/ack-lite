module Hipe
  module Parsie

    module ArrayExtra
      def self.[] ary
        ary.extend self
      end
      def inspct ctxt=InspectContext.new, opts={}
        buffie = ''
        each_with_index do |x,i|
          buffie << "\n" unless i == 0
          buffie << (x.respond_to?(:inspct) ? x.inspct(ctxt,opts) : x.inspect)
        end
        buffie
      end
      def insp
        c = InspectContext.new
        each do |x|
          x.respond_to?(:inspct) ? puts(x.inspct(c,{})) : puts(x.inspect)
        end
        'done.'
      end
    end

    module AttrAccessors
      def boolean_accessor *names
        names.each do |name|
          setter_name = "#{name}="
          getter_name = name
          getter_alias = "#{name}?"
          attr_name = "@#{name}"
          define_method getter_name do
            fail("not defined: #{attr_name}") unless
              instance_variable_defined?(attr_name)
            instance_variable_get attr_name
          end
          define_method setter_name do |x|
            fail("won't set \"#{name}\" to not bool: #{x.inspect}") unless
              x.kind_of?(TrueClass) or x.kind_of?(FalseClass)
            instance_variable_set attr_name, x
          end
          alias_method getter_alias, getter_name
        end
      end
    end


    module TypeMethods
      def bool? mixed
        [TrueClass,FalseClass].include? mixed.class
      end
      def desc_bool name
        "#{name}=#{send(name).inspect}"
      end
    end


    class InspectContext
      attr_accessor :indent
      attr_reader :visited
      def initialize
        @level = 0
        @indent = ''
        @visited = Setesque.new('visited')
      end
      def indent_indent!
        @level += 1
        @indent = ('    ' * @level)
      end
      def dedent_indent!
        @level -= 1
        @indent = ('    ' * @level)
      end
    end


    # used in terminal and nonterminal parses
    # must respond to ui()
    module Inspecty
      Indent = '  '
      def class_basename
        Inspecty.class_basename(self.class)
      end
      def self.class_basename cn
        cn.to_s.split('::').last
      end
      def insp
        ui.puts inspct
        'done.'
      end
      def short
        sprintf('#<%s:%s#%s(%s,%s)>',
          parse_type_short,
          symbol_name_for_debugging,
          @parse_id ? @parse_id : object_id,
          ok_known? ? ( ok? ? 'ok' : '!ok' ) : 'ok?',
          done_known? ? (done? ? 'done' : '!done') : 'done?'
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

    module Lingual
      def oxford_comma items, sep=' and ', comma=', '
        return '()' if items.size == 0
        return items[0] if items.size == 1
        seps = [sep, '']
        seps[0,0] = Array.new(items.size - seps.size, comma)
        items.zip(seps).flatten.join('')
      end
      def const_basename mod
        mod.to_s.match(/(?:^|:)([^:]+)$/)[1]
      end
      def it_is needle, haystack
        haystack.sub(/\bit\b/,needle.to_s)
      end
    end

    module MetaTools
      #
      # this might be a wrapper around thing that will be/have been
      # added to ruby at some point
      #
      class << self
        def enhance(thing)
          define_define_method(thing) if thing.kind_of?(Module)
          add_class_singleton_accessor(thing)
          define_define_method(thing.singleton_class)
          define_alias_thing(thing.singleton_class)
          thing
        end
        alias_method :[], :enhance
      end
    module_function
      def add_class_singleton_accessor(thing)
        unless thing.respond_to? :singleton_class
          sing = class << thing; self end
          sing.send(:define_method, :singleton_class){sing}
        end
        nil
      end
      def define_alias_thing(sing)
        unless sing.respond_to? :alias_method_unless_defined
          class << sing
            def alias_method_unless_defined x, y
              unless instance_methods.include? x.to_s
                alias_method x, y
              end
            end
          end
        end
      end
      def define_define_method(sing)
        unless sing.respond_to? :define_method!
          class << sing
            def define_method! name, &block
              if instance_methods.include? name.to_s
                fail("won't override #{name} for #{self}. check respond_to?")
              end
              define_method(name, &block)
            end
          end
        end
      end
    end


    class RegistryList
      include Enumerable # hm
      def initialize; @children = ArrayExtra[[]] end
      def [] idx; @children[idx] end
      def register obj
        @children << obj
        @children.length - 1
      end
      def each &b
        @children.each(&b)
      end
      def insp; @children.insp; 'done.' end
      def size; @children.size end
      def replace!(idx, value)
        no("no such index to replace: #{idx}") unless idx < @children.length
        old = @children[idx]
        @children[idx] = value
        old
      end
    end


    class Setesque
      # removed Enumerator in ef9ea
      def initialize(name = 'set',&retrieve_block)
        @name = name
        @children = {}
        @order = []
        if retrieve_block
          @retrieve_block = retrieve_block
          if @retrieve_block
            md = /\A(.+)@(.+)\Z/.match(@retrieve_block.to_s)
            me = "#{md[1]}@#{File.basename(md[2])}"
            sing = class << @retrieve_block; self end
            sing.send(:define_method,:inspect){me}
          end
        else
          @retrieve_block = proc{|key|
            @children[key]
          }
        end
      end
      def [] key; @children[key] end
      def retrieve key
        @retrieve_block.call @children[key]
      end
      def each &block
        @order.each do |k|
          thing = retrieve(k)
          block.call(thing, k)
        end
        nil
      end
      def objects
        Enumerator.new self
      end
      def has? key; @children.has_key? key end
      def register key, obj
        fail("won't redefine #{key.inspect}") if
          @children.has_key? key
        @order.push(key)
        @children[key] = obj
        nil
      end
      def replace key, obj
        fail("need a key to replace") unless @children.has_key? key
        old = @children[key]
        @children[key] = obj
        old
      end
      def remove key
        fail("no") unless @children.has_key? key
        @order.delete(key)
        @children.delete(key)
      end
      def clear
        @children.clear
        @order.clear
      end
      def size
        @children.size
      end
      def keys
        @order
      end
    end


    # recursive diff on data structures.  notes of the diff
    # are two element arrays, with the before and after values.
    # identical structures return the empty array.
    #
    module StructDiff
    module_function
      def diff a, b
        if a.respond_to?(:diff)
          a.diff(b)
        else
          case a
            when Array; array_diff(a,b)
            when Hash;  hash_diff(a,b)
            else        obj_diff(a,b)
          end
        end
      end
      def array_diff(a,b)
        if ! b.kind_of?(Array)
          return [{:class=>a.class}, {:class=>b.class}]
        end
        if a.length != b.length
          return [{:length=>a.length}, {:length=>b.length}]
        end
        l = []; r = [];
        a.each_with_index do |x,i|
          d = diff(x, b[i])
          unless d.empty?
            l.push(:idx=>i, :diff=> diff[0])
            r.push(:idx=>i, :diff=> diff[1])
          end
        end
        l.empty? ? [] : [l, r]
      end
      def hash_diff(a, b)
        unless b.kind_of?(Hash)
          return [{:class=>a.class}, {:class=>b.class}]
        end
        ak = a.keys - b.keys
        bk = b.keys - a.keys
        if (bk.any? || ak.any?)
          return [{:different_keys=>ak}, {:different_keys=>bk}]
        end
        l = []; r = [];
        a.each do |(k,v)|
          unless (d=obj_diff(v, b[k])).empty?
            l.push(:key=>k, :diff=>d[0])
            r.push(:key=>k, :diff=>d[1])
          end
        end
        l.empty? ? [] : [l,r]
      end
      def obj_diff(a,b)
        a == b ? [] : [a,b]
      end
    end
  end
end
