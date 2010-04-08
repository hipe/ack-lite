module Hipe
  module Parsie
    module StackeyStream
      # a.k.a. "stream lines tokenizer adapter"
      # modified from hipe-core

      # LooksLike.enhance(self) do |it|
      #   it.looks_like(:stack).if_responds_to %w(closed?, gets)
      #   it.wont_override %w(peek pop push offset)
      # end

      class << self
        def enhance(mixed)
          return mixed if mixed.kind_of?(StackeyStream)
          if looks.ok? mixed
            mixed.extend self
            mixed.extend(TokenizerDescribe) unless mixed.respond_to?(:describe)
            fail("must be an open stream") if mixed.closed?
            mixed.singleton_class.alias_method(:pop!, :pop) unless
              mixed.respond_to?(:pop!)
          else
            fail(looks.not_ok_because(mixed))
          end
        end
        alias_method :[], :enhance
      end

      attr_reader :pushed, :fake_cache, :fake_stack, :has_data,
        :last_line_read, :num_lines_read
      def stackey_stream_init
        @offset = -1
        @fake_cache = {}
        @fake_stack = []
        @has_data = false
        @num_lines_read = 0
        cache_gets
        nil
      end
    private
      attr_reader :offset
      def cache_gets
        # begin
        peek = gets
        # rescue IOError => e
        if (peek.nil?)
          close
        else
          peek.chomp!
          @last_line_read = peek
          @has_data = true
          # popping is what changes our offset, not here!
          push_and_cache_fake(@offset+1, peek) # from -1 to 0
          @num_lines_read += 1
        end
        nil
      end
      def push_and_cache_fake offset, mixed
        fake_cache[offset] = mixed
        fake_stack.push mixed
      end
    public
      def dbg
        {
          :offset => offset,
          :fake_cache => fake_cache,
          :fake_stack => fake_stack
        }
      end
      def token_at x
        if fake_cache[x]
          fake_cache[x]
        else
          nil
        end
      end
      def token_at_final_offset
        fake_stack.any? ? fake_stack.last : last_line_read
      end
      def get_context_near_end
        "#{@offset+1}" << token_at_final_offset.inspect
      end
      def get_context_near x
        "line #{x+1}, near " << token_at(x).inspect
      end
      def push mixed
        push_and_cache_fake(@offset, mixed)
        @offset -= 1
        nil
      end
      def pop
        ret = fake_stack.pop
        unless ret.nil?
          @offset += 1
          if fake_stack.empty?
            cache_gets
          end
          fake_cache[offset] = ret
        end
        ret
      end
      def peek
        fake_stack.last
      end
      def never_had_tokens?
        ! has_data
      end
      def has_no_more_tokens?
        fake_stack.empty?
      end
      def has_more_data?
        ! has_no_more_tokens?
      end
      alias_method :has_more_tokens?, :has_more_data?
    end
  end
end
