require 'ruby-debug'
require 'pp'
me = File.dirname(__FILE__)+'/man-parse'
require me + '/modulettes'
require me + '/cli-litey'

# if it's not a gem yet
parsie_path = File.expand_path('../../..',__FILE__)+'/hipe-parsie-0.0.0/lib'
$:.unshift(parsie_path) unless $:.include?(parsie_path)
require 'hipe-parsie'

module Hipe
  module ManParse
    module Commands
      include CliLitey
      extend self # module_function won't work
      # includes Controller below

      description "parse man pages"
      # add more description lines if you want to make a manpage yourself!

      o "COMMAND"
      x "does the command exist?"
      x "give it the name of a command (like 'sed' or 'grep')"
      def command? opts, command=nil
        return help if opts[:h] || command.nil?
        ui.print(command_found?(command) ? 'yes' : 'no')
      end

      o 'COMMAND'
      x "can the manpage be found?"
      x "give it the name of a command (like 'sed' or 'grep')"
      def man? opts, command=nil
        return help if opts[:h] || command.nil?
        ui.print(man_exists?(command) ? 'yes' : 'no')
      end

      o '[OPTS] [COMMAND]'
      x "will you please try and parse it?"
      x "if COMMAND is provided, tries to read manpage for that,"
      x "else tries to read manpage-like data from STDIN"
      x "if STDIN is tty, will let you type man-page like data in and "
      x "see if it can parse it. (feature?)"
      x 'Options:'
      x ParseOpts = lambda{|o|
        o.on('-v, --verbose', :verbose?,
          'with each token that you parse output debugging info to STDERR',
          '(always on for interactive STDIN mode)'
        )
        o.on('-F, --file', :file?,
          'treat COMMAND as a filename to read manpage text from'
        )
      }
      def parse! opts, command=nil
        return help if opts[:h]
        return short_help unless opts.valid?(&ParseOpts)
        instream, interactive = instream_interactive?(command, opts)
        if interactive && ! opts.verbose?
          opts[:verbose?] = true
        end
        opts.set!(:interactive?, interactive)
        process_parse opts, instream
      end
    private
      def instream_interactive? command, opts
        if opts.file?
          instream = File.open(command, 'r')
          interactive = false
        elsif command.nil?
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
        [instream, interactive]
      end
      def tty_to_instream
        ui.err.puts(
          "trying to read manpage from STDIN! I guess you want to type it.")
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
    end # Commands
    module Controller
      include Open2Str
      private(*Open2Str.public_instance_methods)
      extend self

      def process_parse opts, instream
        response = catch(:interrupt) do
          struct = manpage_stream_to_struct(instream, opts)
          if struct.ok?
            process_struct(opts, struct)
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

      # ( zcat `man --path foo` ) vs. ( man foo | col -bx )
      def manpage_stream_to_struct instream, opts
        opts.set!(:notice_stream, ui.err) # will only be used if verbose?
        assert_necessary_tools
        StackeyStream.enhance(instream)
        structure = grammar[:grammar1].parse!(instream, opts)
        structure
      end

      def command_to_man_string cmd
        out, err = man_exists2(cmd)
        if err.length > 0
          raise Ui[ArgumentError.new(err)]
        end
        cmd = "man #{cmd} | col -bx"
        out, err = open2_str(cmd)
        fail(err) unless ""==err
        out
      end

      def command_found? cmd
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

      def man_exists2 cmd
        open2_str(%{man --path #{cmd}})
      end

      def man_exists? cmd
        out, err = man_exists_2
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
        errs.push("need `col` utility") unless command_found?("col")
        fail(errs.join('. ')) if errs.any?
        nil
      end

    public

      def grammar
        @grammar ||= Hash.new do |h,k|
          case k
          when :grammar1
            h[k] = new_man_page_grammar1
          else
            fail("sorry we don't have a manpage grammar called #{k.inspect}")
          end
        end
      end

    private

      def new_man_page_grammar1
s = <<-HERE
just here for reference, these are example options from manpages

  -metadata key=value
  -loglevel loglevel
  -h, -?, -help, --help
  -C NUM, --context=NUM
  -w or --path
  -S  section_list
  -A NUM, --after-context=NUM
  --colour[=WHEN], --color[=WHEN]


lessons we have learnt about making the regexen:
\b stands for 'bad'  it's more strict than you might think
*all* regexes should probably start with ^ or \A
(depending on how your tokenizer works it's probably the same thing)
*few* should end with $ or \Z


HERE



        Hipe::Parsie::Grammar.new("generic man page") do |g|
          g.add :man_page,  [:before_options_header,
                              :options_header,
                              :options_list,
                              :next_section,
                              :stop
                              ]
          g.add( :before_options_header,
                  [(1..-1), :not_option_line],
                 :capture => false
          )
          g.add :not_option_line, /^(?!OPTION)(.*)$/ #
          g.add :options_header, /^(OPTIONS)$/
          g.add :options_list, [(1..-1), :option_entry]
          g.add :option_entry,
            [:switches, :descriptions, :blank_lines]
          g.add :blank_lines, [(1..-1), :blank_line], :capture=>false
          g.add :blank_line, /^( *)$/
          g.add :switches, [:switch, :more_switches]
          g.add :more_switches, [(0..-1), [:switch_separator, :switch]]
          g.add :switch_separator, /^ *, */
          g.add :switch_separator, /^ *\bor\b */
          g.add( :switch, /^\s{0,9}               # after 14 spaces begins
              (?:                                #   the desc
                (-[?a-z])                        # short name #1
                |
                (--?[a-z0-9][-_a-z0-9]+)         # long name #2
              )
              (?:
                (\[=[_a-z]+\])                   # an optional value #3
                |
                (?:
                  (?:(?:\s\s?|=)([_a-z]+))       # a val w. an equals
                )                                #   or a space #4
                |
                (?: \s
                  ([_a-z]+=[_a-z]+)              # that crazy ffmpeg
                                                 #   key-value thing #5
                )
              )?
              \s*                              # eat remaining w-s
          /xi,                                   # case insensitive, allow
                                                 # whitespace in re
          :named_captures =>
            [:short_name, :long_name,
              :optional, :required, :ridiculous_key_val]
          )
          g.add :descriptions, [(1..-1), :description]
          g.add(:description, /^(?:[[:space:]]{14}|)([^[:space:]].*$)/)
          # :named_captures => [:space_before, :content]
          # )
          g.add(:next_section, /^([^[:space:]]+)/)
          g.add(:stop, :stop)
          g.reference_check
        end
      end # new_man_page_grammar_1
    end # Controller

    module Commands
      include Controller
      extend self # module_function won't work
      private(*Controller.public_instance_methods)
    end
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
