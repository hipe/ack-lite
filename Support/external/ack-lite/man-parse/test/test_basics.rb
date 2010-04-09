require File.dirname(__FILE__)+'/common-setup.rb'

module Hipe
  module ManParse
    describe self do
      class << self
        def skipit msg
          puts "skipping #{msg}"
        end
      end

      def g
        Controller.grammar[:grammar1]
      end

      it "should complain that it is expecting option line (mp-1)" do
        Parsie::Debug.verbose = false
        foo = <<-HERE.unmarginalize!
        slkejfa
        lsejf
        HERE
        rslt = g.parse!(foo)
        rslt.fail.must_match(
          %r{expecting not_option_line or options_header at end of input}
        )
      end

      it "should match the options line (mp-2)" do
        Parsie::Debug.verbose = false
        foo = <<-HERE.unmarginalize!
        abcdef
        ghijk
        OPTIONS
        HERE
        rslt = g.parse!(foo)
        rslt.fail.message.must_match(
         %r{expecting switch at end of input near \"OPTIONS\"})
      end

      it "the big file (mp-3)" do

        path = File.dirname(__FILE__)+'/data/man.grep.col-bx.txt'
        resp = File.open(path) do |fh|
          g.parse!(fh, :verbose? => false)
        end
        assert_equal(43, resp.tree.sexp[:options_list].size)

        fook =  resp.tree.sexp[:options_list][1..-1].map{|x|
          x[:switches].unjoin.map{|y|
            y.to_hash.values_at(:short_name, :long_name).compact
          }
        }.flatten

        FOOK = <<-FOOK.unmarginalize!.one_line!
        -A --after-context -a --text -B --before-context -C --context -b
        --byte-offset --binary-files --colour --color -c --count -D --devices
        -d --directories -E --extended-regexp -e --regexp -F --fixed-strings
        -f --file -G --basic-regexp -H --with-filename -h --no-filename --help
        -I -i --ignore-case -L --files-without-match -l --files-with-matches
        -m --max-count --mmap -n --line-number -o --only-matching --label
        --line-buffered -P --perl-regexp -q --quiet -R -r --include --exclude
        -s --no-messages -U --binary -u --unix-byte-offsets -V --version -v
        --invert-match -w --word-regexp -x --line-regexp -y -Z --null
        FOOK

        assert_equal_array(FOOK.split(' '), fook, 'wow')
      end
    end
  end
end
#in_str = File.read(path)
# resp2 = g.parse!(in_str)
# str1 = <<-HERE.unmarginalize!.one_line!
#   expecting switch_separator or description near line 56,
#   near "[=WHEN]"
# HERE
# str2 = <<-HERE.unmarginalize!.one_line!
#   expecting switch_separator or description near "[=WHEN]"
# HERE
# assert_equal(str1, resp1.fail.message)
# assert_equal(str2, resp2.fail.message)
