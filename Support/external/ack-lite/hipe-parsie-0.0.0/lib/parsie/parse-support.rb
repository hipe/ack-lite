require 'singleton'
require File.dirname(__FILE__)+'/hookey.rb'
require File.dirname(__FILE__)+'/parse-support-modules.rb'

module Hipe
  module Parsie

    # constants for status codes (will be removed :note12)
    #
    OPEN      = 1 # == ! done?
    SATISFIED = 2 # == ok?
    WANTS     = 4


    # collections of things
    #
    Parses = RegistryList.new
    Contexts = RegistryList.new


    # global debugging settings
    #
    class DebugClass
      include Singleton
      def initialize
        @verbose = false
        @look = false
      end
      def verbose?; @verbose end
      def verbose= val; @verbose = val end
      def look?; @looks end
      def look= val; @looks = val end
      def all= val
        self.look = val
        self.verbose = val
      end
      def out= mixed
        @out = mixed
      end
      def out
        @out ||= $stderr
      end
      def puts *a
        out.puts(*a)
      end
    end
    Debug = DebugClass.instance



    # some things (concat parse?) don't make parse objects until they
    # have to, but still we want something there in the slot for debugging
    # and easier implementation of aggregate and cascade functions
    #
    class NilParseClass
      include Singleton
      def is_nil_parse?
        true
      end
      def inspect
        '#<NilParse>'
      end
      alias_method :short, :inspect
      def cascade; end
    end
    NilParse = NilParseClass.instance


    # experimentally all parsers (maybe) will have a parent parser
    # except the RootParse.  This makes some things easier.
    #
    class RootParseClass
      include Singleton
      attr_reader :parse_id
      def initialize
        @parse_id = Parses.register(self)
        @uis = []
      end
      def short
        sprintf('#<%s:%s>','RootParse', parse_id)
      end
      def depth
        0
      end
      def only_child= foo
        @only_child = foo
      end
      def only_child
        @only_child
      end
      def only_child_assert
        no("no") unless @only_child
        @only_child
      end
      %w(validate_down insp cascade).each do |meth|
        define_method(meth){|*a,&b| only_child.send(meth,*a,&b) }
      end
      def ins
        num = only_child.nil? ? '(0)' : '(1):'
        ui.puts "#{' '*depth}#{short}#{num}"
        if only_child.nil?
          ui.puts "  NilClass"
        else
          only_child.ins
        end
      end
      def ui # topmost ui in the parse tree
        @ui ||= Cfg.ui
      end
      def ui_push foo=StringIO.new
        only_child.cascade{|x| x.ui_clear! }
        @uis.push(@ui)
        @ui = foo
        nil
      end
      def ui_pop(do_string_io = true)
        only_child.cascade{|x| x.ui_clear! }
        ret = @ui
        @ui = @uis.pop
        if ret.kind_of?(StringIO)
          ret.rewind
          ret = ret.read
        end
        ret
      end
      def each_existing_child &b
        block.call(only_child_assert, 0)
      end
    end
    RootParse = RootParseClass.instance


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
      include CommonInstanceMethods # children usually want desc_bool?
      @meta = {
        :main_three  => [:wants, :satisfied, :open],
        :alt_two     => [:ok, :done],
        :equivalents => [[:satisfied, :ok]],
        :inverted_equivalents => [[:open, :done]]
      }
      @meta[:all_five] = @meta[:main_three] + @meta[:alt_two]
      class << self
        attr_reader :meta

        def diff(a,b)
          response = {}
          Decisioney.meta[:main_three].each do |item|
            left_val, right_val = a.send(item), b.send(item)
            if left_val != right_val
              response[item] = [left_val, right_val]
            end
          end
          response
        end

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
        Decisioney.diff(self,other)
      end

      def inspct_for_debugging
        sprintf('%s%s',
          wants? ? '___WANTS___' : '_ ',
          short
        )
      end
    end

    # note12: one day we might refactor the response codes to
    # instead all use an object like this
    #
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

    # we weren't sure what we would need this for when we started
    # passing it around to every parser during the course of a parse,
    # but in case we do need it it is here
    #
    # The one thing it is useful for is showing the 'parse tic'
    # during debugging
    #
    class ParseContext
      include CommonInstanceMethods
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
