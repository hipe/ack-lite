require 'open3'
module Hipe
  module ManParse
    module HashExtra
      class << self; def [](mixed); mixed.extend(self); end end

      def values_at *indices
        indices.map{|key| self[key]}
      end
      def keys_to_methods! *ks
        (ks.any? ? ks : keys).each do |k|
          getter_unless_defined k, k
        end
        self
      end
      def getter_unless_defined key, meth
        unless respond_to?(meth)
          meta.send(:define_method, meth){self[key]}
        end
      end
      def slice *indices
        result = HashExtra[Hash.new]
        indices.each do |key|
          result[key] = self[key] if has_key?(key)
        end
        result
      end
    private
      def meta
        class << self; self end
      end
    end
    module RegexpExtra
      def self.[](first,*arr)
        if arr.any?
          re = arr[0]
          name = first
        else
          re = first
          name = nil
        end
        re.extend(self) unless re.kind_of?(RegexpExtra)
        re.name = name if name
        re
      end

      def name= name; @name = name end

      def name; @name | '(regexp)' end

      #
      # return the array of captures and alter the original string to remove
      # everything up to the end of the match.
      # returns nil and leaves the string intact if no match.
      #
      # For now the regexp must have captures in it.
      #
      # Suitable for really simple hand-written top-down recursive decent
      # parsers
      #
      # Example:
      #   prefix_re = RegexpExtra[/(Mrs\.|Mr\.|Dr)/]
      #   name_re = RegexpExtra[/ *([^ ]+)]
      #
      #   str = "Dr. Elizabeth Blackwell"
      #   prefix = prefix_re.parse!(str)
      #   first  = name_re.parse!(str)
      #   last   = name_re.parse!(str)
      #
      def parse! str
        if md = match(str)
          caps = md.captures
          str.replace str[md.offset(0)[1]..-1]
          caps
        else
          nil
        end
      end
      def parse str
        md = nil
        unless md = str.match(self)
          fail("#{name} failed to match against: #{str}")
        end
        md.captures
      end
    end
    class Ui
      attr_accessor :last_command
      %w(puts << print).each do |meth|
        define_method(meth){|*a| out.send(meth,*a) }
      end
      def err
        @err ||= $stderr
      end
      def out
        @out ||= $sdtout
      end

      # wrap existing things to catch them in this app
      module ArgumentError; end
      class << self
        def [] m
          case m
          when ::ArgumentError; m.extend(ArgumentError)
          else; m
          end
        end
      end
    end
    module Open2Str
      def open2_str cmd
        rslt = nil
        Open3.popen3(cmd) do |sin, sout, serr|
          rslt = [sout.read.strip, serr.read.strip]
        end
        rslt
      end
    end
    module OpenSettey
      def open_set hash
        hash.each do |p|
          send("#{p[0]}=", p[1])
        end
      end
    end
    #class Sexpesque < Array  GOTO parsie
    #  def initialize *mixed
    #    super(mixed)
    #  end
    #  def self.[](*mixed)
    #    new(*mixed)
    #  end
    #  def [](mixed)
    #    return super(mixed) unless mixed.kind_of?(Symbol)
    #    idx = index{|x| x[0] == mixed}
    #    super(idx)
    #  end
    #  def []=(key, mixed)
    #    return super(key, mixed) unless key.kind_of?(Symbol)
    #    idx = index{|x| x[0] == key}
    #    if idx
    #      super(2..-1,nil)
    #      self[idx][1] = mixed
    #    else
    #      push self.class.new(key, mixed)
    #    end
    #  end
    #end
    module Lingual
      def oxford_comma items, sep=' and ', comma=', '
        return '()' if items.size == 0
        return items[0] if items.size == 1
        seps = [sep, '']
        seps.insert(0,*Array.new(items.size - seps.size, comma))
        items.zip(seps).flatten.join('')
      end
    end
    class Np
      include Lingual
      def self.[](*arr)
        new(*arr)
      end
      def initialize *arr
        @root = @list = @art = @size = nil
        arr.each do |mixed|
          case mixed
          when String; @root = mixed
          when Array;  @list = mixed
          when Fixnum; @size = mixed
          when Symbol; eat_symbol(mixed)
          else fail("no: #{mixed.inspect}")
          end
        end
      end
      def to_str
        s = @root
        s << 's' if count != 1
        if @list
          s << ': ' << oxford_comma(list)
        end
      end
      alias_method :to_s, :to_str
    private
      def count
        @list ? @list.size : @count
      end
      def eat_symbol sym
        case sym
        when :quoted; @quoted = true
        else
          @art = sym
        end
      end
      def list
        (@list && @quoted) ? @list.map{|x| "\"#{x}\"" } : @list
      end
    end
  end
end
