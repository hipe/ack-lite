require File.dirname(__FILE__)+'/support/common-setup.rb'

class String
  def cleanup num
    re = Regexp.new("^#{' '*num}")
    gsub!(re,'')
    self
  end
end

module Hipe::Parsie
  describe "bad idea - 11" do
    extend SpecExtension

    it "(11-1) validate_down must be valid" do
      parse = evil_grammar.build_start_parse
      RootParse.ui_push
      parse.validate_down
      str = RootParse.ui_pop
      bad = str.grep(/^ *(?! |ok)/)
      all = str.split(/\n/)
      assert_equal(3, all.size)
      assert_equal(0, bad.size)
    end

    it "(11-2) ins must work" do
      parse = evil_grammar.build_start_parse
      str = parse.ins(StringIO.new)
      tgt = %r{\A
        ^\s\s[^\s].+\n
        ^\s\s\s\s[^\s].+\n
        ^\s\s\s\s[^\s].+\n
        ^\s\s\s\s[^\s].+\Z
      }x
      assert_match(tgt, str)
    end

    skipit "(11-5) i am filled with anger" do
      Debug.verbose = true
      parse = evil_grammar.build_start_parse
      foo = <<-HERE.cleanup(6)
      foobric
      barbric
      OPTIONS
             -A NUM, --after-context=NUM
                    Print NUM  lines  of  trailing  context  after  matching  lines.
                    Places  a  line  containing  --  between  contiguous  groups  of
                    matches.

             -a, --text
                    Process a binary file as if it were text; this is equivalent  to
                    the --binary-files=text option.

      HERE
      rslt = evil_grammar.parse!(foo)
      puts rslt.fail.message
    end

    def evil_grammar
      name = 'this grammar'
      Grammar.all.has?(name) ? Grammar.all[name] :
      Grammar.new(name){ |g|
        g.add :man_page,  [:before_options_header,
                            :options_header,
                            :options_list]
        g.add( :before_options_header,
                [(1..-1), :not_option_line],
               :capture => false
        )
        g.add :not_option_line, /\A(?!OPTION)(.*)\Z/ #
        g.add :options_header, /\A(OPTIONS)\Z/
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
            \b\s*                                  # eat remaining w-s
        /xi                                        # case insensitive, allow whitespace in re
        g.add :content_lines, [:content_lines, :content_line]
        g.add :content_lines, :content_line
        g.add :content_line, /\A[[:space:]]{14}([^[:space:]].*)\Z/

        g.reference_check
      }
    end
  end
end
