module Hipe
  module AckLite
    class TmBundle
      def self.singleton
        @singleton ||= TmBundle.new
      end
      def present_search
        require ENV['TM_SUPPORT_PATH'] + '/lib/escape.rb'
        require ENV['TM_SUPPORT_PATH'] + '/lib/osx/plist'
        require ENV['TM_SUPPORT_PATH'] + '/lib/tm/detach.rb'
        parameters = { 
          'searchRegexp' => 'wankers$',
          'searchButtonKey'=>'searchButtonPressed',
          'files' => [{'pattern'=>'*.rb'}], 
          'dirs'  => [{'pattern'=>'.svn'}] 
        }
        show_cmd = %{
         "$DIALOG" nib --load SearchPrompt \
         --center \
         --model #{e_sh parameters.to_plist}
        }
        @token = %x{#{show_cmd}}
        waid_cmd = %{"$DIALOG" nib --wait #{@token}}        
        # TextMate.detach do  -- if we get our own webkit window working
        response = %x{#{waid_cmd}}
        process_search_response response        
        # end
      end
      def process_search_response request
        plist = OSX::PropertyList::load(request)
        puts "your request: <PRE> "+plist.inspect+"</PRE>"
      end
    end
  end
end
