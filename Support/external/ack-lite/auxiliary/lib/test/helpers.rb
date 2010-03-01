module Hipe
  module MinitestExtraClassMethods
    def skipit msg, &b; puts "skipping: #{msg}" end
    def skipbefore &b; end
  end
  module MinitestExtraInstanceMethods
    def with it
      yield it
    end
  end
end

class String
  def test_strip(n)
    gsub(/(?:^ {#{n}}|\n\Z)/, '')
  end
end