require 'open3'
require 'json'
require ENV['TM_SUPPORT_PATH'] + '/lib/escape.rb'    # e_sh
require ENV['TM_SUPPORT_PATH'] + '/lib/osx/plist'    # to_plist
require ENV['TM_BUNDLE_SUPPORT'] + '/external/ack-lite/ack-lite.rb'
require ENV['TM_BUNDLE_SUPPORT'] + '/lib/view-controller.rb' # ViewController


module Hipe

  class Fail     < RuntimeError; end
  class UserFail < Fail; end
  class AppFail  < Fail; end

  module TmBundley
    MyNibRe = /^(\d+) \(Ack Lite\)$/
    def my_loaded_nib_tokens
      str = %x{$DIALOG nib --list}
      str.scan(MyNibRe).map{|m| m[0]}
    end
    def my_first_loaded_nib_token
      my_loaded_nibs.first
    end
    def dispose_all_nibs
      my_loaded_nib_tokens.each do |token|
        dispose_nib_window token
      end
    end
    def dispose_nib_window token
      dispose_cmd = %|$DIALOG nib --dispose #{token}|
      %x{#{dispose_cmd}} # returns empty string
    end
    def plist_decode xml
      OSX::PropertyList::load xml
    end
  end

  module Backtix
    # like using the backtix operator but reads from stdout
    # and stderr.  you can either get the strings back as an array,
    # or it can throw when returns the strings
    # in stdout and stderr

    def backtix2 cmd
      stdin, stdout, stderr = Open3.popen3(cmd)
      out = stdout.read
      err = stderr.read
      return [out, err]
    end

    # this is not always a replacement for running things with backtics!
    # maybe b/c it blocks until EOF?
    def backtix cmd
      out, err = backtix2 cmd
      err.strip!
      if 0 != err.length
        raise Hipe::AppFail.new("failed to run system command -- #{err}")
      end
      out
    end
  end

  # i don't infect core classes
  module Hashey
    def hash_slice h, *keys, &block
      h.each{|k,v| keys << k if block.call(key,val) } if block
      ret = {}
      keys.each{|k| ret[k] = h[k]}
      ret
    end
  end

  module AckLite

    class TmBundle

      include Hashey, Backtix, TmBundley

      include ViewController::ClassMethods # h(), hpp() (html pretty print)

      def self.singleton
        @singleton ||= TmBundle.new
      end

      def initialize
        @view_controller = ViewController.new
      end

      def present_search
        rescue_user_fail do
          model = build_model
          e_model = e_sh model.to_plist

          #if (false && token = my_first_loaded_nib_token)
          #  puts "trying to load existing nib: #{token}"
          #  cmd = "$DIALOG nib --update #{token} --model #{e_model}"
          #  result = %x{#{cmd}}
          #  puts 'my response: '<<hpp(result); # is empty str

          begin # was 'else'
            load_cmd = %{$DIALOG nib --load SearchPrompt } <<
                  %{ --center --model #{e_model}}
            @token = %x{#{load_cmd}}
          end
          wait_cmd = %{$DIALOG nib --wait #{@token}}
          response = %x{#{wait_cmd}}
          process_user_search_request response
        end
      end

      def process_user_search_request request
        plist = plist_decode request
        if plist['eventInfo'] && 'closeWindow' == plist['eventInfo']['type']
          process_search_cancelled
        elsif (plist['eventInfo'] &&
          'searchButtonPressed' == plist['eventInfo']['returnArgument']
        )
          request = prepare_my_search_request plist
          execute_and_render_search_and_save_model request, plist
        else
          raise Hipe::AppFail.new("missing or strange eventInfo: "<<
            plist['eventInfo'].inspect
          )
        end
      end

      def prepare_my_search_request plist
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

      def execute_and_render_search_and_save_model request, plist
        response = Hipe::AckLite::Service.search request
        puts "PLIST:"
        puts hpp(plist)
        puts "SEARCH RESPONSE:"
        puts hpp(response)
        # it didn't throw so we save it
        write_model(plist['model']) if plist['model']
        puts "done."
      end

      def process_search_cancelled
        puts @view_controller.render :close_preview_window
        dispose_nib_window @token
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

      # do whatever and catch any UserFail exceptions, display them
      # in an alert, and clean up our windows.
      def rescue_user_fail
        begin
          yield
        rescue UserFail => e
          resp = %x{$DIALOG alert --alertStyle notice \
            --title 'Ack Lite Notice' --body #{e_sh e.message}  \
            --button1 OK
          }
          info = plist_decode resp
          # puts hpp info   {'buttonClicked'=>0}
          dispose_all_nibs # this actually works! yay
          # hoping we don't have html rendered already..
          puts @view_controller.render :close_preview_window
        end
      end


      # **** refactor start ******
      # @todo refactor to use Textmate module for this kind of thing instead

      # if the user has more than one file/folder selected in the project
      # drawer, assume she wants to search in only those files/folders
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
      # @todo this needs to go away in favor of Textmate module
      def difficult_parse str
        if md = Re2.match(str)
          matches = str.scan(Re1)
          matches.map!{|x| x[0].gsub("'\\''","'")  }
          matches
        else
          raise Hipe::AppFail.new(
            "failed to match selected files string: #{str}"
          )
        end
      end

      # ****** refactor end **********

    end
  end
end
