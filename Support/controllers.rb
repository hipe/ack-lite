require 'open3'
require 'json'
require 'pp' # @todo

module Hipe
  module AckLite

    class Fail < RuntimeError; end
    class UserFail < Fail; end
    class AppFail < Fail; end

    class TmBundle
      # for now, the catch-all controller

      def self.singleton
        @singleton ||= TmBundle.new
      end

      def present_search
        rescue_user_fail do
          require ENV['TM_SUPPORT_PATH'] + '/lib/escape.rb'    # e_sh
          require ENV['TM_SUPPORT_PATH'] + '/lib/osx/plist'
          require ENV['TM_SUPPORT_PATH'] + '/lib/tm/detach.rb'
          require ENV['TM_BUNDLE_SUPPORT'] + '/external/ack-lite/ack-lite.rb'
          model = build_model
          e_model = e_sh model.to_plist
          if (false && token = my_first_loaded_nib_token)
            puts "trying to load existing nib: #{token}"
            cmd = "$DIALOG nib --update #{token} --model #{e_model}"
            result = %x{#{cmd}}
            puts 'my response: '<<mypp(result); # is empty str
          else
            load_cmd = %{$DIALOG nib --load SearchPrompt } <<
                  %{ --center --model #{e_model}}
            @token = %x{#{load_cmd}}
          end
          wait_cmd = %{$DIALOG nib --wait #{@token}}
          response = %x{#{wait_cmd}}
          process_search_request response
        end
      end




      # "protected" (left public for possible tests)

      def rescue_user_fail
        begin
          yield
        rescue UserFail => e
          resp = %x{$DIALOG alert --alertStyle notice \
            --title 'Ack Lite Notice' --body #{e_sh e.message}  \
            --button1 OK
          }
          info = plist_decode resp
          # puts mypp info   {'buttonClicked'=>0}
          dispose_all # this actually works! yay
        end
      end

      MyNibRe = /^(\d+) \(Ack Lite\)$/
      def my_loaded_nib_tokens
        str = %x{$DIALOG nib --list}
        str.scan(MyNibRe).map{|m| m[0]}
      end

      def my_first_loaded_nib_token
        my_loaded_nibs.first
      end

      def dispose_all
        my_loaded_nib_tokens.each do |token|
          dispose token
        end
      end

      def dispose token
        dispose_cmd = %|$DIALOG nib --dispose #{token}|
        %x{#{dispose_cmd}} # empty string
      end

      def backtix2 cmd
        stdin, stdout, stderr = Open3.popen3(cmd)
        out = stdout.read
        err = stderr.read
        return [out, err]
      end

      # this is not a replacement for running things with backtics!
      # maybe b/c it blocks until EOF?
      def backtix cmd
        out, err = backtix2 cmd
        err.strip!
        if 0 != err.length
          raise AppFail.new("failed to run system command -- #{err}")
        end
        out
      end

      def hash_slice h, *keys, &block
        h.each{|k,v| keys << k if block.call(key,val) } if block
        ret = {}
        keys.each{|k| ret[k] = h[k]}
        ret
      end

      def build_model
        model = {
          'searchRegexp' => '',
          'ignoreCase' => false,
          'searchButtonKey'=>'searchButtonPressed', # hack 1
          'dirs'  => [
            {'pattern'=>'.git'}
          ],
          'files' => [
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
        std_out = backtix defaults_cmd
        std_out.strip!
        if 0 == std_out.length
          result = nil
        else
          result = JSON.parse std_out;
        end
        result
      end

      # @todo find better debugging
      def mypp mixed
        h = '<pre>'
        PP.pp(mixed,s='')
        h << self.h(s)
        h << '</pre>'
        h
      end

      def process_search_request request
        plist = plist_decode request
        if plist['eventInfo'] && 'closeWindow' == plist['eventInfo']['type']
          dispose @token
          return
        elsif (plist['eventInfo'] &&
          'searchButtonPressed' == plist['eventInfo']['returnArgument']
        )
          request = prepare_search_request plist
          render_search_and_save_model request, plist
        else
          raise AppFail.new("missing or strange eventInfo: "<<
            plist['eventInfo'].inspect
          )
        end
      end

      def prepare_search_request plist
        file_pats = plist['model']['files'].map{|x|x['pattern']}
        dir_pats  = plist['model']['dirs'].map{|x|x['pattern']}
        re_str    = plist['model']['searchRegexp']
        opt_argv  = []
        opt_argv << '-i' if plist['model']['ignoreCase']
        paths_arg = file_or_dir_paths
        request = Hipe::AckLite::Request.make(
          dir_pats, file_pats, paths_arg, re_str, opt_argv
        )
        request
      end


      # encoders/decoders

      def h(*args)
        CGI.escapeHTML(*args)
      end

      def plist_decode xml
        OSX::PropertyList::load xml
      end

      # @todo find better debugging
      def mypp mixed
        h = '<pre>'
        PP.pp(mixed,s='')
        h << self.h(s)
        h << '</pre>'
        h
      end

      def render_search_and_save_model request, plist
        response = Hipe::AckLite::Service.search request
        puts "PLIST:"
        puts mypp(plist)
        puts "SEARCH RESPONSE:"
        puts mypp(response)
        # it didn't throw so we save it
        write_model(plist['model']) if plist['model']
        puts "done."
      end

      # Below, the 'selected' files refer to the zero or more files that have
      # been selected in the project drawer (multiple by holding butterfly
      # key) (It is required that the user is in a project (folder) for this.)
      # The 'active' file is the file in the buffer that is being edited.
      # (if multiple files are open, it is the top one.)
      # (It is not necessarily written to disk.)
      # Because bundles don't work unless there is one active (not nec.
      # selected) file, TM_FILEPATH is nil IFF the active file is only in the
      # buffer, not on disk.  This should result in a message to the user.
      # There are selected files iff user is in a project.  If she has
      # zero or one selected file, assume she intends to search the project,
      # else search only the selected files
      def file_or_dir_paths
        env = hash_slice(ENV,
          'TM_DIRECTORY' , # the directory the active file
          'TM_FILENAME'  , # basename of the active file
          'TM_FILEPATH'  , # full path of active file
          'TM_PROJECT_DIRECTORY',  # ipso [0,1]
          'TM_SELECTED_FILE', # [0,1]
                    # this is different than the active file. hold butterfly
          'TM_SELECTED_FILES' # zero or more see above
        )
        # puts env.inspect.gsub(",",",<br/>"); exit
        if env['TM_PROJECT_DIRECTORY']
          selected_files = env['TM_SELECTED_FILE'] ?
            difficult_parse(env['TM_SELECTED_FILES']) : [] # sic
          if selected_files.size > 1
            selected_files
          else
            [env['TM_PROJECT_DIRECTORY']]
          end
        elsif env['TM_FILEPATH']
          [env['TM_FILEPATH']]
        else
          raise UserFail.new("Please save current file to search it.")
        end
      end


      # "'bob'\''s file.txt' 'file.txt'" => ["bob's file.txt", "file.txt"]
      Re1 = %r<
        ' ( (?:
              [^'] |
              '\\''
            )+
          )
        '
      >x
      Re2 = Regexp.new("\\A#{Re1}(?: #{Re1})*\\Z")
      def difficult_parse str
        if md = Re2.match(str)
          matches = str.scan(Re1)
          matches.map!{|x| x[0].gsub("'\\''","'")  }
          matches
        else
          raise AppFail.new("failed to match selected files string: #{str}")
        end
      end

      def write_model plist_ruby
        copy = plist_ruby.dup
        copy.delete('searchButtonKey')
        copy.delete('note')
        encoded = copy.to_json
        defaults_cmd = <<-HERE.gsub(/(?:\n|^          )/,' ')
          defaults write com.macromates.textmate
          ackLiteData -string #{e_sh encoded}
        HERE
        backtix defaults_cmd
        nil
      end
    end
  end
end
