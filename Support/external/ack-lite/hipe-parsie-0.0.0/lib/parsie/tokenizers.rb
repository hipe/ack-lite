# @todo this should probably get StackeyStream from man-parse
module Hipe
  module Parsie
    module AbstractTokenizer
      LooksLike.enhance(self).looks_like(:tokenizer).when_responds_to(*%w(
        offset never_had_tokens?  has_no_more_tokens? get_context_near_end
        get_context_near peek pop! push
      ))
    end

    module TokenizerDescribe
      def describe
        # assume there was peeking
        use_offset = offset + 1
        if use_offset == -1
          "at beginning of input"
        # elsif use_offset > last_offset
        elsif has_no_more_tokens?
          if never_had_tokens?
            "and had no input"
          else
            "at end of input near "+get_context_near_end
          end
        else
          this = get_context_near(use_offset)
          "near #{this}"
        end
      end
    end

    class StringLinesTokenizer
      include TokenizerDescribe
      LooksLike.enhance(self).looks_like(:string).when_responds_to :split
      #    looks_like_string()
      #    doesnt_look_like_string_because()


      # this is a sandbox for experimenting with tokenizer interface,
      # for use possibly in something more uselful like in input stream
      # tokenizer
      # note that in lemon the lexer calls the parser

      attr_accessor :final_offset, :offset
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
      # @todo if this is correct, explain it b/c it does
      # not look like push
      def push item
        @lines[@offset] = item
        @offset -= 1
        nil
      end
      def has_more_tokens?
        @offset < final_offset # b/c pop is the only way to go
      end
      def has_no_more_tokens?
        (@offset + 1) > final_offset
      end
      def never_had_tokens?
        @lines.length == 0
      end
      def final_offset
        @final_offset
      end
      def get_line_at idx
        @lines[idx]
      end
      alias_method :token_at, :get_line_at # @todo rename
      def get_context_near x
        get_line_at(x).inspect
      end
      def get_line_at_final_offset
        get_line_at final_offset
      end
      def get_context_near_end
        get_line_at_final_offset.inspect
      end
    end
  end
end
