require 'ruby-debug'
require 'pp'
require 'man-parse/modulettes'
$:.unshift(File.expand_path('../../..',__FILE__)+'/hipe-parsie-0.0.0/lib')
require 'hipe-parsie'

module Hipe
  module ManParse
    module Commands
      include CliLitey
      include Open2Str
      private(*Open2Str.public_instance_methods)
      extend self
      description "parse man pages"
      # add more description lines if you want to make a manpage yourself!

      o "COMMAND"
      x "does the command exist?"
      def exists? opts, command=nil
        return help if opts[:h] || command.nil?
        ui.print(it_exists?(command) ? 'yes' : 'no')
      end

      o 'COMMAND'
      x "can the manpage be found?"
      def man? opts, command=nil
        return help if opts[:h] || command.nil?
        ui.print(man_exists?(command) ? 'yes' : 'no')
      end

      o '[COMMAND]'
      x "will you please try and parse it?"
      x "if COMMAND is provided, tries to read manpage for that,"
      x "else tries to read manpage-like data from STDIN"
      x 'Options:'
      x ParseOpts = lambda{|o|
        o.on('-v, --verbose', :verbose?,
          'with each line(?) that you parse output debugging info to STDERR',
          '(always on for interactive STDIN mode)'
        )
      }
      def parse! opts, command=nil
        return help if opts[:h]
        @interrupted = false
        return short_help unless opts.valid?(&ParseOpts)
        if command.nil?
          if $stdin.tty?
            instream = tty_to_instream
            interactive = true
          else
            instream = $stdin
            interactive = false
          end
        elsif $stdin.tty?
          instream = command_to_instream command
          interactive = false
        else
          fail("Won't both read from STDIN and command name: \"#{comm}\"")
        end
        response = catch(:interrupt) do
          struct = manpage_stream_to_struct(instream, opts)
          if struct.ok?
            PP.pp(struct, ui) #will have to change
          else
            ui.err.puts struct.fail.message
          end
          :got_to_end
        end
        case response
        when :interrupted
          ui.puts "\ncaught interrupt signal. quitting."
        when :got_to_end
          ui.err.puts "done."
        else
          ui.err.puts "unexpected exit : #{response.inspect}"
        end
      end

      def grammar
        @grammar ||= Hash.new do |h,k|
          case k
          when :grammar1
            new_man_page_grammar1
          else
            fail("sorry we don't have a manpage grammar called #{k.inspect}")
          end
        end
      end

    private
      def s; Sexpesque; end

      # ( zcat `man --path foo` ) vs. ( man foo | col -bx )
      def manpage_stream_to_struct instream, opts
        opts.set!(:notice_stream, ui.err) # will only be used if verbose?
        assert_necessary_tools
        StackeyStream.enhance(instream)
        structure = grammar[:grammar1].parse!(instream, opts)
        structure
      end

      def tty_to_instream
        ui.err.puts "trying to read manpage from STDIN! I guess you want to type it."
        ui.err.puts "Type Ctrl-D for EOF, Ctrl-C to quit"
        catch_interrupts
        $stdin
      end

      def command_to_instream command
        string = command_to_man_string command
        instream = StringIO.new(string)
        instream.rewind
        instream
      end

      def catch_interrupts
        trap('INT') { throw(:interrupt, :interrupted) }
      end

      def command_to_man_string cmd
        cmd = "man #{cmd} | col -bx"
        out, err = open2_str(cmd)
        fail(err) unless ""==err
        out
      end

      def it_exists? cmd
        which = %{which #{cmd}}
        out, err = open2_str(which)
        if (''==err && ''==out)
          false
        elsif (''==err && 0<out.length)
          true
        else
          fail("huh? "+{:out=>out,:err=>err}.inspect)
        end
      end

      def man_exists? cmd
        out, err = open2_str(%{man --path #{cmd}})
        if (''==err && 0 < out.length)
          true
        elsif (''==out && 0 < err.length && /\ANo manual/=~ err )
          false
        else
          fail("huh? "+{:out=>out,:err=>err}.inspect)
        end
      end

      # this assumes 'man --path' is available (note1:.)
      def assert_necessary_tools
        errs = []
        errs.push("need `col` utility") unless it_exists?("col")
        fail(errs.join('. ')) if errs.any?
        nil
      end

      if (false) # just here for reference, these are example options from manpages
        s = <<-HERE
          -metadata key=value
          -loglevel loglevel
          -h, -?, -help, --help
          -C NUM, --context=NUM
          -w or --path
          -S  section_list
          -A NUM, --after-context=NUM
          --colour[=WHEN], --color[=WHEN]
        HERE
      end

      def new_man_page_grammar1
        # Grammar.all.has?(name) ? Grammar.all[name]
          Hipe::Parsie::Grammar.new("generic man page") do |g|
          g.add :man_page,  [
                              :before_options_header,
                              :options_header,
                              :options_list
                            ]
          g.add( :before_options_header,
                  [(1..-1), :not_option_line],
                 :capture => false
          )
          g.add :not_option_line, /\A(?!OPTION)/ # /(\A(?!OPTION).*)\Z/
          g.add :options_header, /\AOPTIONS\Z/   # /\A(OPTIONS)\Z/
          g.add :options_list, [:options_list, :option_entry]
          g.add :options_list, :option_entry

          g.add :option_entry,
            [:main_thing_list, :content_lines, :blank_line]
          g.add :blank_line, ''
          g.add :main_thing_list, [:main_thing_list, :more_main_things]
          g.add :main_thing_list, :main_thing
          g.add :more_main_things, [(0..-1), [:thing_separator, :main_thing]]
          g.add :thing_separator, / *, */
          g.add :thing_separator, / *\bor\b */
          g.add :main_thing, /\s*\b
              (-[?a-z]|--?[a-z0-9][-_a-z0-9]+)       # the name part
              (?:
                (\[=[_a-z]+\])                       # an optional value
                |
                (?:
                  (?:(?:\s\s?|=)([_a-z])+)           # a val w. an equals or a space
                )
                |
                (?: \s
                  ([_a-z]+=[_a-z]+)                  # that crazy ffmpeg key-value thing
                )
              )?
              \b\s*
          /xi
          g.add :content_lines, [:content_lines, :content_line]
          g.add :content_lines, :content_line
          g.add :content_line, /\A[[:space:]]{14}([^[:space:]].*)\Z/

          g.reference_check
        end
      end
    end # Commands
  end # ManParse
end # hipe
# def man_troff_parse io, struct
#   @io = io
#   @struct = struct
#   StackeyStream.enhance(io)
#   io.pop until io.peek == ".SH OPTIONS\n"
#   return parse_fail("couldn't find OPTIONS section") unless io.peek
#   debugger
#   'x'
# end

# def parse_fail msg
#   msg << " anywhere before end of stream" if @io.closed?
#   @struct[:man_parse_fail] = true
#   @struct[:man_parse_fail_reason] = msg
#   @struct[:man_parse_line] = io.offset
#   false
# end
