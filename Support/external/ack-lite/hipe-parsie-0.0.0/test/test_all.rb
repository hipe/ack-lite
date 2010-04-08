require 'minitest/autorun'  # unit and spec
require 'ruby-debug'

root =  File.dirname(__FILE__)
# keep the format consistent below or see Rakefile
require root + '/meta-tools.rb'
require root + '/table.rb'
require root + '/tokenizer.rb'
require root + '/stackey-stream.rb'
require root + '/string.rb'
require root + '/regexp.rb'
require root + '/parse-support.rb'
require root + '/union-basic.rb'
require root + '/concat-basic.rb'
require root + '/structured-basic.rb'
require root + '/left-recursion-basic.rb'
require root + '/left-recursion-page-45.rb'
require root + '/regexp-pushback-and-range.rb'
require root + '/it-was-all-a-bad-idea.rb'
