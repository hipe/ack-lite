module Hipe
  module Parsie

    module NaySayer; def no msg; raise No.new(msg) end end

    module AryExt
      def self.[] ary
        ary.extend self
      end
      def insp
        c = InspectContext.new
        each do |x|
          x.respond_to?(:inspct) ? puts(x.inspct(c)) : puts(x.inspect)
        end
        nil
      end
    end

    module Productive
      include NaySayer
      def symbol_name= name;
        Productive.make_getter(self,:symbol_name,name)
      end
      def production_id= production_id
        Productive.make_getter(self,:production_id,production_id)
      end
      def table_name= foo
        Productive.make_getter(self,:table_name,foo)
      end
      def self.make_getter(obj,meth,val)
        no("don't clobber this") if obj.respond_to? meth
        class<<obj; self end.send(:define_method,meth){val}
      end
    end


    module Terminesque
      def hypothetical?; false end
    end


    module ParseStatusey
      include NaySayer
      def done?
        no("asking done when done is nil") if @done.nil?
        @done
      end
      def ok?
        no("asking ok when ok is nil") if @ok.nil?
        @ok
      end
    end

    module Inspecty
      def class_basename
        self.class.to_s.split('::').last
      end
      def insp; $stdout.puts inspct end
      def inspct_tiny
        sprintf("<%s%s#%s>",
          class_basename.scan(/[A-Z]/).join(''),
          @symbol_name.inspect,
          @parse_id
        )
      end

      # block - true or false whether to skip
      def inspct_attr(ll,arr,ind='',&b)
        arr = [arr] unless arr.kind_of? Array
        arr.each do |a|
          val = instance_variable_get(a)
          next if block_given? && ! yield(val)
          ll << sprintf("#{ind}#{a}=%s",val.inspect)
        end
        nil
      end

    end

    module Misc
      def bool? mixed
        [TrueClass,FalseClass].include? mixed.class
      end
    end

    module SymbolAggregatey
      def _spawn ctxt, claz
        if ctxt.token_frame_production_parsers.has? production_id
          parse = ctxt.token_frame_production_parsers[production_id]
          ParseReference.new parse
        else
          p = claz.new(self, ctxt) # note2
          ctxt.tfpp.register(production_id, p)
          p.resolve_children
          p
        end
      end
    end

    module AggregateParsey
      def production
        Productions[@production_id]
      end
      def parse_context
        ParseContext.all[@context_id]
      end
      def symbol_name
        production.symbol_name
      end
      def _resolve_children
        ctxt = parse_context
        @children = production.children.map do |sym|
          sym.spawn(ctxt)
        end
        AryExt[@children]
      end
    end

    class InspectContext
      attr_reader :indent, :visiting
      def initialize
        @indent = ''
        @visiting = Setesque.new('nodes rendering')
      end
      def indent_indent!
        @indent << '  '
      end
    end

    module AggregateParseInspecty
      include Inspecty
      def inspct_extra ll, ctx, opts
      end
      def inspct ctx=InspectContext.new, opts={}
        if ctx.visiting.has? parse_id
          opts[:word] = true
          opts[:visited] = true
        else
          ctx.visiting.register parse_id, nil
        end
        a = opts[:visited] ? '(again:)' : ''
        ind = ctx.indent.dup
        ctx.indent_indent!
        ll = []
        ll << sprintf("#<#{a}%s:%s",class_basename,@parse_id.inspect)
        ll << sprintf("symbol_name=%s",symbol_name.inspect)
        inspct_attr(ll,%w(@done @ok))
        inspct_extra(ll,ctx,opts)
        ch = @children
        if opts[:word]
          if (@children.respond_to? :size)
            ll << "@children(#{ch.size})"
          else
            inspct_attr(ll,'@children')
          end
          return (ll*', '+' >')
        end
        l = []
        l << (ll*",\n #{ind}")
        if @children.respond_to? :size
          l << " #{ind}@children(#{ch.size})="
          _inspct_children(l,ind,ctx,opts)
        else
          inspct_attr(l, '@children',ind)
        end
        l.last << '>'
        l * "\n"
      end

      def _inspct_children l, my_ind, ctx, opts
        return @children.inspect unless @children
        last = @children.length - 1
        @children.each_with_index do |c,i|
          if (i==0)
            s = ("  #{my_ind}["<<c.inspct(ctx, opts))
          else
            s = ("   #{my_ind}"<<c.inspct(ctx, opts))
          end
          s << ']' if i==last
          l << s
        end
      end
    end

    module LookieLocky
      include NaySayer
      def look_lock
        sett = parse_context.visiting(:look)
        if sett.has? parse_id
          throw :look_wip,  {:pid=>parse_id}
        else
          sett.register(parse_id, :look_wipping)
        end
        nil
      end

      def look_unlock
        sett = parse_context.visiting(:look)
        rm = sett.remove(parse_id)
        no("unexpected value") unless :look_wipping == rm
        nil
      end

    end

    # very experimental!!!

    class HypotheticController
      include NaySayer
      def initialize(new_parent, orig, caller)
        @new_parent_id = new_parent.parse_id
        @caller_parse_id = caller.parse_id
        @orig_parse_id = orig.parse_id
      end

      def caller; Parses[@caller_parse_id] end

      # there are no victimless crimes
      def victim; Parses[@orig_parse_id] end

      attr_reader :new_parent_id
      def new_parent; Parses[@new_parent_id] end

      def kidnap
        no('no') unless new_parent.children == :no
        nu_children = []
        caller_parse_id = caller.parse_id
        metas = []
        itr = victim.instance_variable_get('@in_the_running')
        victim.children.each_with_index do |p,i|
          pid = p.kind_of?(Terminesque) ? nil : p.parse_id
          is_caller = (! pid.nil?) && pid == caller_parse_id
          metas << {
            :is_caller => is_caller,
            :idx => i
          }
        end
        num = metas.select{|x| x[:is_caller] }.size
        no("caller should be there exactly once") unless num == 1
        to_take = metas.select{|x| ! x[:is_caller] }.map{|x| x[:idx] }
        victim.kidnapping_notify(to_take)
        metas.each do |meta|
          if meta[:is_caller]
            nu_children << ParseReference.new(caller)
          else
            nu_children << victim.children[meta[:idx]]
          end
        end
        victim.kidnapped_notify(to_take,self)
        new_parent.instance_variable_set('@children', nu_children)
        new_parent.instance_variable_set('@hypothetical', NotHypothetical)
        nil
      end

    end

    module Hypothetic
      include NaySayer
      def kidnap!
        @hypothetic.kidnap
      end

      def init_hypothetic orig, caller
        @hypothetical = IsHypothetical
        %w(@done @ok @in_the_running).each do |s|
          instance_variable_set(s, orig.instance_variable_get(s))
        end
        @hypothetic = HypotheticController.new(self, orig, caller)
        no("no") if @children
        @children = NoChildren
        nil
      end
    end
  end
end
