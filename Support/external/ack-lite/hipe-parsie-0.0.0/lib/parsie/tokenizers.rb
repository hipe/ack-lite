module Hipe
  module Parsie
    module TokenizerDescribe
      def describe
        # assume there was peeking
        use_offset = offset + 1
        if use_offset == -1
          "at beginning of input"
        # elsif use_offset > last_offset
        elsif is_at_end_of_input?
          if is_emtpy_stream_or_file?
            "and had no input"
          else
            "at end of input near "+get_line_at_final_offset.inspect
          end
        else
          this = get_line_at(use_offset)
          "near \"#{this}\""
        end
      end
    end
    class StringLinesTokenizer
      include TokenizerDescribe
      # this is a sandbox for experimenting with tokenizer interface,
      # for use possibly in something more uselful like in input stream
      # tokenizer
      # note that in lemon the lexer calls the parser

      attr_accessor :has_more_tokens, :final_offset, :offset
      def initialize str
        @lines = str.split("\n")
        @offset = -1;
        @final_offset = @lines.length - 1
      end
      def peek
        hypothetical = @offset + 1
        return nil if hypothetical > @final_offset
        @lines[hypothetical]
      end
      def pop!
        return nil if @offset > @final_offset
        @offset += 1 # let it get one past last offset
        @lines[@offset]
      end
      # this is experimental.  if we want to add end-of stack hooks
      # we should change this to replace_current
      def push item
        @lines[@offset] = item
        @offset -= 1
        nil
      end
      def has_more_tokens?
        @offset < final_offset # b/c pop is the only way to go
      end
      def is_at_end_of_input?
        (@offset + 1) > final_offset
      end
      def is_emtpy_stream_or_file?
        @lines.length == 0
      end
      def final_offset
        @final_offset
      end
      def get_line_at idx
        @lines[idx]
      end
      def get_line_at_final_offset
        get_line_at final_offset
      end
    end
    module StackTokenizerAdapter
      These = %w(peek pop push)
      class << self
        def enhance(mixed)
          mixed.extend(self)
          if mixed.respond_to?(:pop) && ! mixed.respond_to?(:pop!)
            class << mixed
              alias_method :pop!, :pop
            end
          end
          unless mixed.respond_to?(:describe)
            mixed.extend(TokenizerDescribe)
          end
          mixed.stack_tokenzier_adapter_init
          mixed
        end
        alias_method :[], :enhance
        def looks_like_stack? mixed
          doesnt_look_like_stack_because(mixed).empty?
        end
        def doesnt_look_like_stack_because mixed
          missing = []
          These.each do |this|
            missing.push(this) unless mixed.respond_to?(this)
          end
          missing
        end
      end
      def stack_tokenzier_adapter_init
      end
    end
  end
end
