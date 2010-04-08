require File.dirname(__FILE__)+'/parent-child.rb'

module Hipe
  module Parsie

    module FaileyMcFailerson
      def fail= parse_fail
        no("type assert fail") unless parse_fail.kind_of? ParseFail
        @last_fail = parse_fail
      end
      def fail(mixed=nil)
        if mixed
          no(mixed)
        else
          @last_fail
        end
      end
      def failed?
        ! @last_fail.nil?
      end
    end

    module StrictOkAndDone
      def done_known?
        ! @done.nil?
      end
      def done?
        no("asking done when done is nil") if @done.nil?
        @done
      end
      def open?
        ! done?
      end
      def ok_known?
        ! @ok.nil?
      end
      def ok?
        no("asking ok when ok is nil") if @ok.nil?
        @ok
      end
    end

    module BubbleUppable
      def bubble_up obj
        if ! obj.kind_of? PushBack
          No.no('no for now')
        end
        if ! parent?
          No.no('for now all parses have parent except root parse')
        end
        if parent == RootParse
          parse_context.pushback obj
        else
          if parent.respond_to? :bubble_up
            parent.bubble_up obj
          else
            No.no("how come parent no have bubble_up?")
          end
        end
      end
    end

    #
    # we were avoiding this for some reason but ...
    #
    module Parsey
      include FaileyMcFailerson, StrictOkAndDone

      def parse_context
        ParseContext.all[@context_id]
      end
      def tic
        parse_context.tic
      end
      def singleton_class
        class << self; self end
      end
    end
  end
end
