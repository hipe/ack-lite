require 'pp' # @todo: this is for debugging only
require 'erb'

module Hipe
  module AckLite
    class TmBundle
      class ViewController
        TemplateDir = ENV['TM_BUNDLE_SUPPORT'] + '/view'

        module ClassMethods

          def h(*args)
            CGI.escapeHTML(*args)
          end

          # @todo find better debugging
          def hpp mixed
            h = '<pre>'
            PP.pp(mixed,s='')
            h << self.h(s)
            h << '</pre>'
            h
          end

        end # ClassMethods

        def hash_to_binding(h)
          eval(h.keys.map{|k| "#{k} = h[#{k.inspect}]"} * ';')
          binding
        end

        def render template_name, args = {}
          binding = hash_to_binding args
          path = File.join(TemplateDir,%{#{template_name}.erb})
          str = File.read(path)
          ERB.new(str).result(binding)
        end
      end # ViewController
    end # TmBundle
  end # AckLite
end # Hipe
