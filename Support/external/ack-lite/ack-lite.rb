require 'open3'

module Hipe
  module AckLite
    # kind of ridiculous to model this as 'Service' or a 'Proxy' but the
    # idea is that there is only one interface to it -- a request in a
    # certain structure and a response in a certain structure

    module Failey; end
    class Fail < RuntimeError
      include Failey
    end
    class Request < Struct.new(
      :directory_ignore_patterns,
      :file_include_patterns,
      :search_paths,
      :regexp_string,
      :regexp_opts_argv
    )
      def self.make *args
        if (args.size == 1 && args[0].kind_of?(Hash))
          req = self.new
          args[0].each do |pair|
            req.send("#{pair[0]}=",pair[1])
          end
        else
          req = self.new(*args)
        end
        req
      end
    end
    class SearchResponse < Struct.new(:command, :list); end

    module Service
      class << self

        def search *args
          request = make_request *args
          if request.kind_of? Hash
            request = Request.make request
          end
          cmd = self.find_cmd request
          cmd <<  " | xargs grep --line-number #{request.regexp_string}"
          resp = SearchResponse.new
          resp.list = lines_from_command cmd
          resp.command = cmd
          resp
        end

        def files *args
          cmd = find_cmd make_request *args
          lines_from_command cmd
        end

        # "private"
        def make_request(*args)
          if (args.size==1 && args[0].kind_of?(Request))
            args[0]
          else
            Request.make *args
          end
        end

        # from Textmate:
        # escape text to make it useable in a shell script as one “
        # word” (string)
        def e_sh(str)
        	str.to_s.gsub(/(?=[^a-zA-Z0-9_.\/\-\x7F-\xFF\n])/n, '\\').
        	  gsub(/\n/, "'\n'").sub(/^$/, "''")
        end

        def find_cmd request
          paths_part = request.search_paths.map{|x| e_sh(x)} * ' '
          cmd = "find -L #{paths_part} "
          and_me = []
          dirs = request.directory_ignore_patterns
          files = request.file_include_patterns
          if 0 < dirs.length
            and_me << (
              ' -not \( -type d \( ' <<
              (dirs.map{|x| "-name #{x}"} * ' -o ') <<
              ' \) -prune  \)'
            )
          end
          if 0 < files.length
            and_me <<  (
              '\( ' <<
              (files.map{|x| "-name \"#{x}\""} * ' -o ') <<
              ' \)'
            )
          end
          cmd << ( and_me * ' -a ')
          cmd
        end

        def lines_from_command cmd
          stdin, stdout, stderr = Open3.popen3(cmd)
          out = stdout.read
          err = stderr.read
          err.strip!
          if (0 < err.length)
            raise Fail.new(err << "(from command: #{cmd})")
          end
          out.split("\n")
        end
      end
    end
  end
end
