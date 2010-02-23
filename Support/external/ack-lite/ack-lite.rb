module Hipe
  module AckLite
    module Failey; end
    class Fail < RuntimeError
      include Failey
    end
    # kind of ridiculous to call it a 'Service' or a 'Proxy' but the
    # idea is that this is your only interface to it, this and Cli

    class Request < Struct(:files, :folders, :regex, :regex_opts, :path); end
    class ValidRequest < Struct(:files, :folders, :regex, :path); end
    module Service
      def search request
        valid = validate request
      end

      def validate request
        valid = ValidRequest.new
        if ! File.dir?(request.path)
          raise Fail.new("path must exist: #{request.path}")
        end
        valid.path = request.path
        opts = 0
        request.regex_opts.each do |letter|
          case letter
            when 'i': opts |= Regexp::IGNORECASE
            when 'm': opts |= Regexp::MULTILINE
            when 'x': opts |= Regexp::EXTENDED
            else raise new Fail("unrecognized option: #{letter}." <<
              "Expecting 'i','m', or 'x'")
          end
        end
        begin
          regex = Regex.new(request.regex, opts)
        rescue RegexpError => e
          e.extend Failey
          raise e
        end
        valid.regex = regex
        valid.folders = folders
        valid.files = files
        valid
      end
    end
  end
end
