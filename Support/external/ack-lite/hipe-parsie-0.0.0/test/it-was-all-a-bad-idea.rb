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

    it "(11-5) i am filled with anger" do
      # Debug.verbose = true
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
      if rslt.ok?
        sexp = rslt.tree.sexp
        entries = sexp[:options_list].all(:option_entry)
        assert_equal(2, entries.size)
        these = entries[0][:switches].unjoin
        names = these.map(&:to_hash)
        assert_equal({:short_name=>'-A', :required=>'NUM'}, names[0])
        assert_equal({:long_name=>"--after-context", :required=>"NUM"},
           names[1])
      else
        assert(false)
        puts rslt.fail.message
      end
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
        g.add :options_list, [(1..-1), :option_entry]
        g.add :option_entry,
          [:switches, :descriptions, :blank_lines]
        g.add :blank_lines, [(1..-1), :blank_line], :capture=>false
        g.add :blank_line, /^( *)$/
        g.add :switches, [:switch, :more_switches]
        g.add :more_switches, [(0..-1), [:switch_separator, :switch]]
        g.add :switch_separator, / *, */
        g.add :switch_separator, / *\bor\b */
        g.add( :switch, /\s*
            (?:
              (-[?a-z])                        # short name #1
              |
              (--?[a-z0-9][-_a-z0-9]+)         # long name #2
            )
            (?:
              (\[=[_a-z]+\])                   # an optional value #3
              |
              (?:
                (?:(?:\s\s?|=)([_a-z]+))       # a val w. an equals
              )                                # or a space #4
              |
              (?: \s
                ([_a-z]+=[_a-z]+)              # that crazy ffmpeg
                                               # key-value thing #5
              )
            )?
            \b\s*                              # eat remaining w-s
        /xi,                                   # case insensitive, allow
                                               # whitespace in re
        :named_captures =>
          [:short_name, :long_name, :optional, :required, :ridiculous_key_val]
        )
        g.add :descriptions, [(1..-1), :description]
        g.add :description, /\A[[:space:]]{14}([^[:space:]].*)\Z/
        g.reference_check
      }
    end
  end
end
