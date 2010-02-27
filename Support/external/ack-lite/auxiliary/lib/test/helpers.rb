module Hipe
  module Skippy
    def skipit msg, &b; puts "skipping: #{msg}" end
    def skipbefore &b; end
  end
end

class String
  def test_strip(n)
    gsub(/(?:^ {#{n}}|\n\Z)/, '')
  end
end