require 'open3'
require 'json'

module Hipe
  module AckLite

    class Fail < RuntimeError; end

    class TmBundle

      def self.singleton
        @singleton ||= TmBundle.new
      end

      def present_search
        require ENV['TM_SUPPORT_PATH'] + '/lib/escape.rb'
        require ENV['TM_SUPPORT_PATH'] + '/lib/osx/plist'
        require ENV['TM_SUPPORT_PATH'] + '/lib/tm/detach.rb'
        model = build_model
        show_cmd = %{
         "$DIALOG" nib --load SearchPrompt \
         --center \
         --model #{e_sh model.to_plist}
        }
        @token = %x{#{show_cmd}}
        wait_cmd = %{"$DIALOG" nib --wait #{@token}}
        response = %x{#{wait_cmd}}
        process_search_request response
      end

      def build_model
        model = {
          'searchRegexp' => '',
          'searchButtonKey'=>'searchButtonPressed', # hack 1
          'dirs'  => [
            # {'pattern'=>'.svn'},
            {'pattern'=>'.git'}
          ],
          'files' => [
             # {'pattern'=>'*.rb'},
             # {'pattern'=>'*.py'},
             # {'pattern'=>'*.php'},
             # {'pattern'=>'*.css'},
             {'pattern'=>'*.js'}
          ]
        }
        if saved_model = read_model
          model.merge! saved_model
        end
        model
      end

      def read_model
        defaults_cmd = "defaults read com.macromates.textmate ackLiteData"
        stdin, stdout, stderr = Open3.popen3(defaults_cmd)
        out = stdout.read
        err = stderr.read
        if 0 != err.length
          raise new Fail.new("what happened to model? -- #{err}")
        end
        if 0 == out.strip!.length
          nil
        else
          decoded = JSON.parse out;
          decoded
        end
      end

      def process_search_request request
        plist_ruby = OSX::PropertyList::load request
        if plist_ruby['model'] # should always be here
          write_model plist_ruby['model']
        end
        puts "<PRE>";
        puts "thing: "+plist_ruby.inspect
        puts "</PRE>";
      end

      def write_model plist_ruby
        copy = plist_ruby.dup
        copy.delete('searchButtonKey')
        encoded = copy.to_json
        defaults_cmd = <<-HERE.gsub(/(?:\n|^          )/,' ')
          defaults write com.macromates.textmate
          ackLiteData -string #{e_sh encoded}
        HERE
        stdin, stdout, stderr = Open3.popen3(defaults_cmd)
        out = stdout.read
        err = stdout.read
        if 0 != err.length
          raise Fail.new("couldn't write to defaults: #{err}")
        end
        nil
      end
    end
  end
end
