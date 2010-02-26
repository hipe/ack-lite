module Hipe

  module Parsie
    module UserFailey;                                end
    class Fail < RuntimeError;                        end
    class AppFail < Fail;                             end
    class ParseParseFail < Fail;  include UserFailey; end

    class StringLinesTokenizer
      attr_accessor :has_more_tokens
      def initialize str
        @lines = str.split("\n")
        @offset = -1;
        @last_offset = @lines.length - 1
      end
      def pop
        return nil if @offset > @last_offset
        @offset += 1 # let it get one past last offset
        @lines[@offset]
      end
      def has_more_tokens?
        @offset < @last_offset # b/c pop is the only way to go
      end
      def describe
        if @offset == -1
          "at beginning of input"
        elsif @offset > @last_offset
          if @lines.length == 0
            "at end of input"
          else
            "at end of input near "+@lines[@offset-1].inspect
          end
        else
          "near \""+@lines[@offset]+'"'
        end
      end
    end

    class Cfg
      def parse! mixed
        tokenizer = build_tokenizer mixed
        parse = @start_symbol.spawn
        while token = tokenizer.pop
          parse.look token
          break if parse.done?
        end
        if ! parse.ok?
          @parse_fail = ParseFail.new(tokenizer, parse)
          nil
        elsif tokenizer.has_more_tokens?
          @parse_fail = ParseFail.new(tokenizer, parse)
          nil
        else
          parse
        end
      end
    end

    class ParseFail < Fail
      include UserFailey
      def initialize tokenizer, parse
        @tokenizer = tokenizer
        @parse = parse
      end
      def describe
        ex = @parse.expecting
        prepositional_phrase = @tokenizer.describe
        "expecting #{ex.join(' or ')} #{prepositional_phrase}"
      end
    end

    class Cfg
      @tables = {}
      class << self; attr_reader :tables; end

      def self.clearTables
        @tables.clear
      end

      def initialize name, &block
        raise ParseParseFail.new("already have table \"#{name}\"") if
          Cfg.tables.has_key? name
        Cfg.tables[name] = self
        @name = name
        @entries = {}
        block.call self
        table_done
      end

      def add name, mixed
        parser = make_parser mixed
        if @entries.has_key? name
          if @entries[name].kind_of? Union
            union = @entries[name]
          else
            union = Union.new(@entries[name])
          end
          union.add parser
        end
        parser.name = name
        parser.table = @name
        @start_symbol = parser if @entries.size == 0
        @entries[name] = parser
      end

      def table_done
        @entries.each{|p| p[1].table_done }
      end

      def make_parser mixed
        case mixed
          when Regexp: RegexpSymbol.new(mixed)
          when Symbol: SymbolSymbol.new(mixed)
          when Array:  ConcatSymbol.new(mixed)
          when String: StringSymbol.new(mixed)
          else raise ParseParseFail.new("no: #{mixed.inspect}")
        end
      end

      def parse_fail
        @parse_fail
      end

      def parse! mixed
        tokenizer = build_tokenizer mixed
        parse = @start_symbol.spawn
        while token = tokenizer.pop
          parse.look token
          break if parse.done?
        end
        if ! parse.ok?
          @parse_fail = ParseFail.new(tokenizer, parse)
          nil
        elsif tokenizer.has_more_tokens?
          @parse_fail = ParseFail.new(tokenizer, parse)
          nil
        else
          parse
        end
      end

      def build_tokenizer mixed
        case mixed
        when String: StringLinesTokenizer.new(mixed)
        else raise ParseParseFail.new("no: #{mixed.inspect}")
        end
      end
    end

    Grammar = Cfg

    module Symbolic
      def name; @name end
      def name= name;
        raise ParseParseFail.new('no') if @name
        @name = name
      end
      def table= table_name
        @table_name = table_name
      end
    end

    module ParseStatusey
      def done?
        raise AppFail.new('no') if @done.nil?
        @done
      end
      def ok?
        raise AppFail.new('no') if @ok.nil?
        @ok
      end
    end

    class StringSymbol
      include Symbolic
      def initialize string
        raise ParseParseFail("no").new if
          (""==string || !string.kind_of?(String))
        @string = string
        @done = false
        @ok = false
      end
      def table_done; end
      def spawn
        StringParse.new(@string)
      end
    end

    class StringParse
      include ParseStatusey
      def initialize string
        @string = string
        @done = false
        @ok = false
      end
      def look token
        if (token==@string)
          @done = true
          @ok = true
        end
      end
      def expecting
        @done ? ['end of input'] : [@string.inspect]
      end
    end

    class RegexpSymbol
      include Symbolic
      attr_accessor :re
      def initialize re; @re = re end
      def table_done; end
      def spawn
        RegexpParse.new(@re, @name)
      end
    end

    class RegexpParse
      include ParseStatusey
      attr_accessor :matches
      def initialize(re, name)
        @re = re
        @name = name
        @done = false
        @ok = false
      end
      def expecting
        @done ? ['end of input'] : [@name]
      end
      def look str
        md = @re.match(str)
        @ok = ! md.nil?
        @done = @ok
        @matches = md.nil? ? nil : md.captures
      end
    end


    class UnionSymbol
      include Symbolic
      def initialize parse
        @name = parse.name
        @children = [parse]
      end
      def add child
        raise ParseParseFail.new("children of a union must "<<
        "have the same name: #{@name.inspect}, "<<
        "#{child.name.inspect}") unless @name == child.name
        @children.push child
        nil
      end
    end

    class ConcatSymbol
      include Symbolic
      def initialize ary
        @children = ary
      end
    end

  end
end
