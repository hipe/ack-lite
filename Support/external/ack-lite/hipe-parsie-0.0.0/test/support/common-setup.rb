require 'ruby-debug'
require 'minitest/autorun'  # unit and spec
me = File.expand_path('../..',File.dirname(__FILE__))
require me + '/lib/hipe-parsie.rb'
require me + '/test/support/minitest-extlib.rb'
require me + '/test/support/parsie-extlib.rb'
