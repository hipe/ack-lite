require 'open3'

module Hipe
  module AckLite
    module Failey; end
    class Fail < RuntimeError
      include Failey
    end
    # kind of ridiculous to call it a 'Service' or a 'Proxy' but the
    # idea is that this is your only interface to it, this and Cli

    class Request < Struct.new(:files, :dirs, :path, :regexp_str, :regexp_opts_str); end
    class ValidRequest < Struct.new(:files, :dirs, :path, :regexp); end
    module Service
      class << self
        def search request
          valid = validate request
        end

        # from Textmate:
        # escape text to make it useable in a shell script as one “word” (string)
        def e_sh(str)
        	str.to_s.gsub(/(?=[^a-zA-Z0-9_.\/\-\x7F-\xFF\n])/n, '\\').gsub(/\n/, "'\n'").sub(/^$/, "''")
        end

        def find_cmd request
          cmd = "find -L #{e_sh request.path} "
          and_me = []
          if 0 < request.dirs.length
            and_me << (' -not \( -type d \(' << (request.dirs.map{|x| "-name #{x}"} * ' -o ') <<
              ' \) -prune  \)' )
          end
          if 0 < request.files.length
            and_me <<  ('\( ' << (request.files.map{|x| "-name \"#{x}\""} * ' -o ') << ' \)' )
          end
          cmd << ( and_me * ' -a ')
          cmd
        end

        def files request
          cmd = find_cmd request
          stdin, stdout, stderr = Open3.popen3(cmd)
          out = stdout.read
          err = stderr.read
          err.strip!
          if (0 < err.length)
            raise Fail.new(err)
          end
          out.split("\n")
        end

        def validate request
          valid = ValidRequest.new
          if ! File.directory?(request.path)
            raise Fail.new("path must exist: #{request.path}")
          end
          valid.path = request.path
          opts = 0
          letters = request.regexp_opts_str.split('')
          letters.each do |letter|
            case letter
              when 'i': opts |= Regexp::IGNORECASE
              when 'm': opts |= Regexp::MULTILINE
              when 'x': opts |= Regexp::EXTENDED
              else raise Fail.new(%|unrecognized option: '#{letter}'. | <<
                "Expecting 'i','m', or 'x'")
            end
          end
          begin
            regexp = Regexp.new(request.regexp_str, opts)
          rescue RegexpError => e
            e.extend Failey
            raise e
          end
          valid.regexp = regexp
          valid.dirs = request.dirs
          valid.files = request.files
          valid
        end
      end
    end
  end
end
