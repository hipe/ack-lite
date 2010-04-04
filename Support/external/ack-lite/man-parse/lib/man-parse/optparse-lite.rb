module Hipe
  module ManParse
    module Lingual
      def oxford_comma items, sep=' and ', comma=', '
        return '()' if items.size == 0
        return items[0] if items.size == 1
        seps = [sep, '']
        seps.insert(0,*Array.new(items.size - seps.size, comma))
        items.zip(seps).flatten.join('')
      end
    end
    class Np
      include Lingual
      def self.[](*arr)
        new(*arr)
      end
      def initialize *arr
        @root = @list = @art = @size = nil
        arr.each do |mixed|
          case mixed
          when String; @root = mixed
          when Array;  @list = mixed
          when Fixnum; @size = mixed
          when Symbol; eat_symbol(mixed)
          else fail("no: #{mixed.inspect}")
          end
        end
      end
      def to_str
        s = @root
        s << 's' if count != 1
        if @list
          s << ': ' << oxford_comma(list)
        end
      end
      alias_method :to_s, :to_str
    private
      def count
        @list ? @list.size : @count
      end
      def eat_symbol sym
        case sym
        when :quoted; @quoted = true
        else
          @art = sym
        end
      end
      def list
        (@list && @quoted) ? @list.map{|x| "\"#{x}\"" } : @list
      end
    end
    module OptparseLite
      include Lingual
      class << self
        def parse_args argv, ui
          options = argv.select { |piece| piece =~ /^-/ }
          argv   -= options
          opts = Hash[* options.map do |flag|
            key,value = flag.match(/\A([^=]+)(?:=(.*))?\Z/).captures
            [key.sub(/^--?/, '').intern, value.nil? ? true : value ]
          end.flatten ]
          enhance opts, ui
          [opts, argv]
        end
        def display_doc_proc ui, &block # sig change from orig in assess
          opts = enhance({}, ui).documenting!
          block.call(opts)
          opts.flush_documentation!(ui)
        end
        def build_doc_matrix &block
          opts = enhance({},nil).documenting!
          block.call(opts)
          opts.flush_doc_matrix!
        end
      private
        def enhance(opts, ui)
          opts.extend HashExtra
          opts.extend self # kind of suck. god module
          opts.ui = ui
          opts
        end
      end

      attr_accessor :ui, :doc_matrix

      def documenting!
        self.doc_matrix = []
        @documenting = true;
        self
      end

      def documenting?; @documenting end

      def flush_documentation! ui
        dm = doc_matrix
        w = dm.map{|x|x[0]}.compact.map(&:length).inject(0){|m,v| m>v ? m : v}
        dm.each{|(l,r,x)| ui.puts(x ? x : ("  %-#{w}s  %s" % [l,r] )) }
      end

      def flush_doc_matrix!
        self.doc_matrix ||= []
        resp = doc_matrix
        self.doc_matrix = []
        resp
      end

      # @param args ignored
      def valid?(args=nil, &block)
        self.args = args.dup unless args.nil?
        yield self if block_given?
        is_valid = ! errors.any?
        if (bads = bad_opts_hack).any?
          is_valid = false
          s = bads.length > 1 ? 's' : ''
          ui.err.puts("#{prefix}unrecognized option#{s} "<<
            oxford_comma(bads.map(&:inspect)))
        end
        if ! args.nil? && ! args_valid?
          is_valid = false
        end
        is_valid
      end

      def args= arr
        @args = arr
      end

      def args_valid?
        if @args.any?
          ui.err.puts Np['unexpected argument',:quoted, @args].to_s
          false
        else
          true
        end
      end

      def x mixed = ''
        if mixed.kind_of?(Proc)
          if documenting?
            matrix = OptParseLite.build_doc_matrix(&mixed)
            doc_matrix.concat matrix
          else
            mixed.call(self)
          end
        elsif documenting?
          doc_matrix.push([nil,nil,mixed])
        end
      end

      def parse! str, make_method, *args, &block
        opts = args.last.kind_of?(Hash) ? args.pop : {}
        if documenting?
          doc_matrix.push [str, args.shift]
          doc_matrix.concat args.map{|x| [nil, x]}
          if opts.has_key?(:default)
            doc_matrix.last[1] = [doc_matrix.last[1],
            "(default: #{opts[:default].inspect})"].compact * ' '
            # let subsequent options see defaults of previous options
            normalize!(nil, make_method, opts[:default])
          end
          nil
        else
          opt = parse_parse(str)
          ok = true
          if (found = (opt.names & keys)).any?
            ok = process_found_switches(opt, found, make_method, opts)
          elsif opts.has_key?(:default)
            normalize!(nil, make_method, opts[:default])
            handled make_method
          else
            normalize!(nil, make_method, nil)
            handled make_method
          end
          yield() if block_given? && ok
          ok
        end
      end

      alias_method :on, :parse!

      # makes getter, must not exist already either as method or as element
      def set! name, value
        fail("options already set: #{name.inspect}") if (
          respond_to?(name) || has_key?(name)
        )
        self[name] = value
        getter_unless_defined name, name
      end

    private
      def normalize! used_name, make_method, value
        if used_name.nil?
          self[make_method] = value
        else
          self[make_method] = self.delete(used_name)
        end
        handled make_method
        getter_unless_defined make_method, make_method
        nil
      end

      def prefix
        "#{ui.last_command.app_name} #{ui.last_command.name_pretty}: "
      end

      def meta
        class << self; self end
      end

      def bad_opts_hack
        (keys - handled).map do |sym|
          sym.to_s.length > 1 ? "--#{sym}" : "-#{sym}"
        end
      end

      OnCommas = /, */

      def short_or_long
        @short_or_long ||= RegexpExtra[
         /\A *(?:-([a-z0-9])|--(?:\[(no-)\])?([a-z0-9][-a-z0-9]+)) */i
        ]
      end

      def opt_or_required
        @opt_or_required ||= RegexpExtra[
          /\A *=(?:([A-Z_]+)|\[([A-Z_]+)\]) */
        ]
      end

      def handled *names
        @handled ||= []
        if names.any?
          @handled.concat names
        else
          @handled
        end
      end

      def process_found_switches opt, found, make_method, opts
        fail('no') unless found.any?
        ok = true
        handled(*found)
        if found.size > 1
          add_error("Can't handle multiple arguments for #{opt.name}")
          ok = false
        else
          used_name = found.first
          value = self[used_name]
          if opt.noable
            re = Regexp.new('^'+Regexp.escape(opt.noable))
            value = re !~ (used_name.to_s)
            normalize! used_name, make_method, value
          elsif value==true
            if opt.required?
              add_error("#{opt.name.inspect} missing required value "<<
              "#{opt.argument_name}")
              ok = false
            else
              normalize! used_name, make_method, value
            end
          else
            if ! opt.takes_argument?
              add_error("#{opt.name.inspect} does not take an argument "<<
              "(#{value.inspect})")
              ok = false
            else
              normalize! used_name, make_method, value
            end
          end
        end
        ok
      end

      def add_error msg
        errors.push msg
        ui.puts "#{prefix}#{msg}"
        nil
      end

      def errors
        @errors ||= []
      end

      class OptParseParse < Struct.new(:names, :takes_argument, :required,
        :optional, :argument_name, :short, :long, :noable)
        alias_method :required?, :required
        alias_method :optional?, :optional
        alias_method :takes_argument?, :takes_argument
        def name
          long.any? ? long.first : short.first
        end
      end

      def parse_parse str
        names, reqs, opts, short, long = [[],[],[],[],[]]
        noable = nil
        str.split(OnCommas).each do |opt|
          caps = nil
          pp_fail("#{str.inspect}") unless caps = short_or_long.parse!(opt)
          names.push(caps[0] || caps[2])
          long.push "--#{caps[2]}" if caps[2]
          short.push "-#{caps[0]}" if caps[0]
          if caps[1]
            pp_fail("huh?") if noable
            noable = caps[1]
            this = "#{caps[1]}#{caps[2]}"
            long.push "#--{this}"
            names.push this
          end
          if caps = opt_or_required.parse!(opt)
            (caps[0] ? reqs : opts).push(caps[0] || caps[2])
          end
          pp_fail("unparsable remains: #{str.inspect}") unless opt.empty?
        end
        pp_fail("can't have both required and optional arguments: "<<
          str.inspect) if reqs.any? && opts.any?
        arg_names = opts | reqs
        pp_fail("let's not take arguments with no- style opts") if
          noable && arg_names.any?
        pp_fail("spell the argument the same way each time: "<<
          oxford_comma(arg_names)) if arg_names.length > 1
        OptParseParse.new(
          names.map(&:to_sym), opts.any? || reqs.any?,
          reqs.any?, opts.any?, arg_names, short, long, noable
        )
      end

      def pp_fail msg
        fail("parse parse fail: bad option syntax synatx: #{msg}")
      end
    end
  end
end
