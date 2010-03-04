module Hipe
  module Parsie
    module NonterminalInspecty
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
        ind = ctx.indent.dup
        ctx.indent_indent!
        if false && opts[:word]
          return "#<again##{@parse_id}>"
        end
        a = opts[:visited] ? '(again:)' : ''
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
          ss = c ? c.inspct(ctx, opts) : c.inspect
          if (i==0)
            s = ("  #{my_ind}["<<ss)
          else
            s = ("   #{my_ind}"<<ss)
          end
          s << ']' if i==last
          l << s
        end
      end
    end
  end
end
