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
      :grep_opts_argv,
      :shell_command  # experimental - for internal use and user feedback
    )
      private
      def initialize(*args); super end

      public
      def self.build *args
        if (args.size == 1 && args[0].kind_of?(Hash))
          req = self.new
          args[0].each do |pair|
            req.send("#{pair[0]}=",pair[1])
          end
        else
          req = self.new(*args)
        end
        req.grep_opts_argv ||= []
        req
      end
    end
    class SearchResponse < Struct.new(:command, :list); end

    module Service

      # the values below must be either 'true' or string, the former
      # only for switches that don't take arguments, the latter for the latter
      DefaultGrepOpts = {
        '--line-number'      => true,
        '--extended-regexp'  => true,
        '--binary-files'     => 'without-match',
        '--with-filename'    => true
      }
      GrepShortToLong = {
        '-n' => '--line-number',
        '-E' => '--extended-regexp',
        '-I' => '--binary-files', # careful! hack!
        '-H' => '--with-filename'
      }

      class << self

        #
        # if block given, as each result string is produced,
        # block will be called with two arguments: the string and the result
        # object at that point.
        # @return SearchResponse
        #
        def search *args, &block
          request = build_request(*args)
          cmd = request.shell_command
          if block_given?
            each_line cmd, block
          else
            resp = SearchResponse.new
            resp.list = lines_from_command cmd
            resp.command = cmd
            resp
          end
        end

        def files *args
          cmd = find_cmd_head build_request(*args)
          lines_from_command cmd
        end

        def build_request(*args)
          request = nil
          if (args.size==1 && args[0].kind_of?(Request))
            request = args[0]
          else
            request = Request.build(*args)
          end
          unless request.shell_command
            cmd = find_cmd_head request
            opts = render_grep_opts request
            cmd << " -exec grep #{opts} "<<
                    " #{request.regexp_string}  \{\} ';'"
            request.shell_command = cmd
          end
          request
        end



        # "private" *******


        def render_grep_opts request
          use_opts = DefaultGrepOpts.dup
          # this kind of sucks - it's like a mini-optparse hack
          _keys = request.grep_opts_argv.select{|str| /^-/ =~ str }
          keys = Hash[* _keys.zip(Array.new(_keys.length, true)).flatten ]
          use_opts.reject!{ |k,v| keys[k] || keys[GrepShortToLong[k]] }
          opts = ''
          use_opts.each do |pair|
            if true==pair[1]
              opts << "#{pair[0]} "
            else
              opts << "#{pair[0]}=#{pair[1]} "
            end
          end
          opts << (request.grep_opts_argv * ' ')
          opts
        end

        # from Textmate:
        # escape text to make it useable in a shell script as one “
        # word” (string)
        def e_sh(str)
        	str.to_s.gsub(/(?=[^a-zA-Z0-9_.\/\-\x7F-\xFF\n])/n, '\\').
        	  gsub(/\n/, "'\n'").sub(/^$/, "''")
        end

        def find_cmd_head request
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

        def each_line cmd, block
          result = nil
          Open3.popen3(cmd) do |stdin, stdout, stderr|
            result = SearchResponse.new(cmd, [])
            stdout.each do |line|
              result.list << line
              block.call(line, result)
            end
            assert_no_errors stderr, cmd
          end
          result
        end

        def assert_no_errors stderr, cmd
          err = stderr.read
          err.strip!
          if (0 < err.length)
            raise Fail.new(err << "(from command:___#{cmd}___)")
          end
        end

        def lines_from_command cmd
          stdin, stdout, stderr = Open3.popen3(cmd)
          out = stdout.read
          assert_no_errors stderr, cmd
          out.split("\n")
        end
      end
    end
  end
end
