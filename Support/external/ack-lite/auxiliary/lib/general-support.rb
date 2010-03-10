module Hipe
  module Parsie

    module Misc
      def bool? mixed
        [TrueClass,FalseClass].include? mixed.class
      end
      def desc_bool name
        "#{name}:#{send(name) ? 'yes' : 'no'}"
      end
      def no taxes
        raise No.new taxes
      end
    end

    module AryExt
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

    class Setesque
      include Misc
      class Enumerator
        include Enumerable
        def initialize settie
          @thing = settie
        end
        def each
          @thing.each do |p|
            obj = @thing.retrieve p[0]
            yield [p[0], obj]
          end
        end
      end
      def initialize(name = 'set',&retrieve_block)
        @name = name
        @children = {}
        @retrieve_block = retrieve_block
        if @retrieve_block
          md = /\A(.+)@(.+)\Z/.match(@retrieve_block.to_s)
          me = "#{md[1]}@#{File.basename(md[2])}"
          class << @retrieve_block; self end.send(:define_method,:inspect){me}
        end
      end
      def [] key; @children[key] end
      def retrieve key
        @retrieve_block.call @children[key]
      end
      def objects
        Enumerator.new self
      end
      def has? key; @children.has_key? key end
      def register key, obj
        no(%{won't redefine "#{key}" grammar}) if
          @children.has_key? key
        @children[key] = obj
        nil
      end
      def replace key, obj
        no(%{need a key to replace}) unless @children.has_key? key
        old = @children[key]
        @children[key] = obj
        old
      end
      def remove key
        no("no") unless @children.has_key? key
        @children.delete(key)
      end
      def clear; @children.clear end
      def size; @children.size end
      def keys; @children.keys end

    end

    class RegistryList
      include Enumerable # hm
      def initialize; @children = AryExt[[]] end
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

    # used in terminal and nonterminal parses
    module Inspecty
      def class_basename
        Inspecty.class_basename(self.class)
      end
      def self.class_basename cn
        cn.to_s.split('::').last
      end
      def insp; $stdout.puts inspct; 'done.' end
      def inspct_tiny
        sprintf("<%s%s#%s>",
          class_basename.scan(/[A-Z]/).join(''),
          symbol_name.inspect,
          @parse_id ? @parse_id : object_id
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

    module UserFailey
      # something the user did wrong in creating grammars, etc
    end

    class Fail < RuntimeError
      # base class for all exceptions originating from this library
    end

    class AppFail < Fail
      # we did something wrong internally in this library
    end

    class ParseParseFail < Fail
      # something the user did wrong in construting a grammar
      include UserFailey
    end

    class ParseFail < Fail
      # half the reason parsers exist is to do a good job of reporting these
      # then there's this

      include UserFailey # not sure about this

      attr_reader :parse, :tokenizer

      def self.from_parse_loop tokenizer, parse
        ex = parse.expecting.uniq
        expecting = ex.size == 0 ? 'no more input' : ex.join(' or ')
        prepositional_phrase = tokenizer.describe
        msg = "expecting #{expecting} #{prepositional_phrase}"
        pf = ParseFail.new(msg)
        pf.instance_variable_set('@parse', parse)
        pf.instance_variable_set('@tokenizer', tokenizer)
        pf
      end

      def describe
        message
      end

    end

    No = AppFail # internal shorthand

  end
end
