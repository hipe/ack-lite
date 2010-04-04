require 'open3'
require File.dirname(__FILE__)+'/optparse-lite'

module Hipe
  module ManParse
    module HashExtra
      class << self; def [](mixed); mixed.extend(self); end end

      def values_at *indices
        indices.map{|key| self[key]}
      end
      def keys_to_methods! *ks
        (ks.any? ? ks : keys).each do |k|
          getter_unless_defined k, k
        end
        self
      end
      def getter_unless_defined key, meth
        unless respond_to?(meth)
          meta.send(:define_method, meth){self[key]}
        end
      end
      def slice *indices
        result = HashExtra[Hash.new]
        indices.each do |key|
          result[key] = self[key] if has_key?(key)
        end
        result
      end
    private
      def meta
        class << self; self end
      end
    end
    module RegexpExtra
      def self.[](first,*arr)
        if arr.any?
          re = arr[0]
          name = first
        else
          re = first
          name = nil
        end
        re.extend(self) unless re.kind_of?(RegexpExtra)
        re.name = name if name
        re
      end

      def name= name; @name = name end

      def name; @name | '(regexp)' end

      #
      # return the array of captures and alter the original string to remove
      # everything up to the end of the match.
      # returns nil and leaves the string intact if no match.
      #
      # For now the regexp must have captures in it.
      #
      # Suitable for really simple hand-written top-down recursive decent
      # parsers
      #
      # Example:
      #   prefix_re = RegexpExtra[/(Mrs\.|Mr\.|Dr)/]
      #   name_re = RegexpExtra[/ *([^ ]+)]
      #
      #   str = "Dr. Elizabeth Blackwell"
      #   prefix = prefix_re.parse!(str)
      #   first  = name_re.parse!(str)
      #   last   = name_re.parse!(str)
      #
      def parse! str
        if md = match(str)
          caps = md.captures
          str.replace str[md.offset(0)[1]..-1]
          caps
        else
          nil
        end
      end
      def parse str
        md = nil
        unless md = str.match(self)
          fail("#{name} failed to match against: #{str}")
        end
        md.captures
      end
    end
    class Ui
      attr_accessor :last_command
      %w(puts << print).each do |meth|
        define_method(meth){|*a| out.send(meth,*a) }
      end
      def err
        @err ||= $stderr
      end
      def out
        @out ||= $sdtout
      end
    end
    module Open2Str
      def open2_str cmd
        rslt = nil
        Open3.popen3(cmd) do |sin, sout, serr|
          rslt = [sout.read.strip, serr.read.strip]
        end
        rslt
      end
    end
    module OpenSettey
      def open_set hash
        hash.each do |p|
          send("#{p[0]}=", p[1])
        end
      end
    end
    class Sexpesque < Array
      def initialize *mixed
        super(mixed)
      end
      def self.[](*mixed)
        new(*mixed)
      end
      def [](mixed)
        return super(mixed) unless mixed.kind_of?(Symbol)
        idx = index{|x| x[0] == mixed}
        super(idx)
      end
      def []=(key, mixed)
        return super(key, mixed) unless key.kind_of?(Symbol)
        idx = index{|x| x[0] == key}
        if idx
          super(2..-1,nil)
          self[idx][1] = mixed
        else
          push self.class.new(key, mixed)
        end
      end
    end
    module StackeyStream
      # peek and pop a stream line by line.
      # gives an IO stream peek(), pop(), offset(), push()
      # (push does not write to files just keeps it in memory)
      # This is latest version here.  modified from hipe-core

      def self.enhance io
        return io if io.kind_of? StackeyStream
        [:peek, :pop, :push, :offset].each do |meth|
          raise Fail.new("won't override '#{meth}'") if io.respond_to? meth
        end
        [:closed?, :gets].each do |meth|
          raise Fail.new("to be a StackeyStream you must define #{meth}") unless
            io.respond_to? meth
        end
        fail("must be an open stream") if io.closed?
        io.extend self
        io.stackey_stream_init
        io
      end
      def get_line_at x
        if @hmm[x]
          @hmm
        elsif x == (@hmm.length + 1) && has_more_data?
          peek # not robust!
        else
          "won't get line at offset #{x}"
        end
      end
      def push mixed
        @pushed.push mixed
        @offset += 1
        nil
      end
      def pop
        ret = @pushed.pop
        @hmm[@offset] = ret
        stackey_stream_update_peek unless ret.nil?
        ret
      end
      def stackey_stream_init
        class << self
          attr_reader :pushed, :offset
        end
        @has_data = false
        @hmm = []
        @pushed = []
        @offset = -1
        stackey_stream_update_peek
        nil
      end
      def peek
        @pushed.last
      end
      def is_emtpy_stream_or_file?
        ! @has_data
      end
      def is_at_end_of_input?
        @pushed.empty?
      end
      def has_more_data?
        ! is_at_end_of_input?
      end
    private
      def stackey_stream_update_peek
        peek = gets
        if (peek.nil?)
          close
        else
          @has_data = true
          @offset += 1
          @pushed.push peek
        end
        nil
      end
    end
    module CliLitey
      include Lingual
      private(*Lingual.public_instance_methods)
      class << self
        def included klass
          class << klass
            def description desc=nil
              if desc.nil?
                @description ||= []
              else
                description.push desc
              end
            end
          end
        end
      end
      module ArgumentErro; end # just for hack disabling below
      module RuntimeErro; end
      def invoke argv
        argv = argv.map(&:dup)
        return help_no_args unless argv.any?
        return help_requested(*argv[1..-1]) if help_requested?(argv[0])
        return help_bad_command(*argv) unless valid_command?(argv[0])
        meth = argv.shift
        ui.last_command = get_command(meth)
        opts, args = OptparseLite.parse_args(argv,ui)
        begin
          send(meth, opts, *args)
        rescue ArgumentErro, RuntimeErro => e
          ui.puts e.message
          cmd = get_command(meth)
          if cmd.help.any? && ( opts[:h] || opts[:help] )
            show_full_command_help(cmd)
          else
            short_help(cmd)
          end
        end
        ui.puts # not sure about this
      end
    private
      def o str
        next_command_usage.push str
      end
      def x str
        next_command_help.push str
      end
      def ui
        @ui ||= Ui.new
      end
      def help_no_args
        help_general
      end
      def help_general
        show_usage
        show_full_description
        show_commands
      end
      def prefix
        ''
      end
      def show_usage
        ui.puts "Usage: #{invocation_name} COMMAND [OPTS] [ARGS]"
      end
      def looks_like_header? line
        /\A[ a-z]*: *\Z/i =~ line
      end
      def show_full_description(desc = description,header_indent='',body_indent=nil)
        if desc.any?
          ui.print "#{header_indent}Description: "
          ui.puts if desc.size > 1
          desc.each do |line|
            if line.kind_of? Proc
              OptparseLite.display_doc_proc(ui, &line)
            elsif looks_like_header? line
              ui.puts # not sure about this
              ui.print header_indent
              ui.puts line
            else
              ui.print(body_indent) if body_indent
              ui.puts line
            end
          end
        end
      end
      def invocation_name
        File.basename($PROGRAM_NAME)
      end
      def help_requested? command
        ['-h','--help','help'].include?(command)
      end
      def show_full_command_help cmd
        cmd = get_command(cmd) unless cmd.kind_of?(Command)
        show_usage_for_command(cmd) if cmd.usage.any?
        if cmd.help.any?
          ui.puts
          show_full_description(cmd.help, '', ' '*margin_a)
        end
      end
      def trace_parse str
        if md = /\A([^:]+):([^:]+)(?::in `([^']+)')?\Z/.match(str)
          path, line, method = md.captures
          bn = File.basename(path)
          h = {:path=>path, :line=>line, :method=>method, :basename=>bn}
          {:method=>:meth,:basename=>:bn,:line=>:ln}.each{|(a,b)| h[b] = h[a]}
          h
        else
          {}
        end
      end
      def help
        info = trace_parse(caller[0])
        show_full_command_help info[:method]
      end
      def short_help cmd=nil
        if cmd.nil?
          info = trace_parse(caller[0])
          cmd = get_command(info[:method])
        elsif ! cmd.kind_of?(Command)
          cmd = get_command(cmd)
        end
        show_usage_for_command(cmd) if cmd.usage.any?
        invite_to_more_help_for_command(cmd) if cmd.help.any?
      end

      def help_requested command=nil, *ignore
        if command.nil?
          help_general
        elsif valid_command? command
          help_for_command command
        else
          ui.puts "#{prefix}unrecognized command \"#{command}\""
          show_did_you_mean(command)
          help_general
        end
      end
      def help_bad_command command, *whatever
        ui.puts "i don't know how to #{command}."
        show_did_you_mean(command)
        invite_to_more_help
      end
      def command_names
        @valid_command_names ||= (public_instance_methods - ['invoke'])
      end
      def valid_command? command
        maybe = did_you_mean(command)
        case maybe.size
        when 0
          valid = false
        when 1
          valid = true
          command.replace maybe.first
        else
          ui.puts("did you mean" << oxford_comma(maybe,' or ')<<'?')
          valid = false
        end
        valid
      end
      def margin_a
        @margin_a ||= 2
      end
      def margin_b
        @margin_b ||= 4
      end
      def show_usage_for_command cmd
        cmd = get_command(cmd) unless cmd.kind_of?(Command)
        if cmd.usage.any?
          a, b = margins
          ui.puts "Usage: #{invocation_name} #{cmd.name_pretty} #{cmd.usage.join("\n")}"
        end
      end
      def margins
        [' '*margin_a, ' '*margin_b]
      end
      def show_commands
        base_commands = commands.select{|c| c.base_command? }
        unless base_commands.any?
          ui.puts "This service doesn't accept commands."
          return
        end
        ui.puts
        ui.puts 'Commands:'
        width = base_commands.map{|c| c.name.length }.max + margin_a + margin_b
        a, b = margins
        base_commands.each do |c|
          ui.puts sprintf("#{a}%-#{width}s#{b}#{c.help.first}",c.name)
        end
        ui.puts
        invite_to_more_command_help
      end
      def invite_to_more_command_help
        ui.puts "type -h after a command or subcommand name for more help"
      end
      def invite_to_more_help_for_command cmd
        cmd = get_command(cmd) unless cmd.kind_of?(Command)
        if cmd.help.any?
          ui.puts "try \"#{invocation_name} #{cmd.name_pretty} -h\" for more information."
        end
      end
      def show_did_you_mean command
        if (did_u_mean = did_you_mean(command)).any?
          ui.puts("did you mean "<<oxford_comma(did_u_mean,' or ')<<'?')
        end
      end
      def did_you_mean command
        meth_like = command.gsub(/:-/,'_')
        re = Regexp.new(Regexp.escape(command))
        matches = command_names.grep(re)
        if matches.size > 0 && (idx = matches.index(meth_like))
          matches = [meth_like]
        end
        matches
      end
      def invite_to_more_help
        ui.puts "try \"#{invocation_name} -h\" for help."
      end
      class Command < Struct.new(:full_name, :usage, :help, :app_name)
        Re = /\A(?:.*_)?([^_]*)\Z/
        def initialize(*a)
          super(*a)
          self.usage = [] unless usage
          self.help  = [] unless help
        end
        def name
          @name ||= begin
            full_name.match(Re)[1]
          end
        end
        def name_pretty
          name.gsub('_',' ')
        end
        def base_command?
          name == full_name
        end
      end
      def commands
        @commands ||= begin
          command_names.map do |cmd|
            get_command(cmd)
          end
        end
      end
      def get_command name
        Command.new(name, command_usage[name], command_help[name], invocation_name)
      end
      def command_usage
        @command_usage ||= {}
      end
      def command_help
        @command_help ||= {}
      end
      def next_command_help
        @next_command_help ||= []
      end
      def next_command_usage
        @next_command_usage ||= []
      end
      def method_added method_sym
        if next_command_help.any? || next_command_usage.any?
          if next_command_usage.any?
            command_usage[method_sym.to_s] = @next_command_usage
            @next_command_usage = nil
          end
          if next_command_help.any?
            command_help[method_sym.to_s] = @next_command_help
            @next_command_help = nil
          end
        end
      end
    end
  end
end
