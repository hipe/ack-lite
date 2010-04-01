require 'ruby-debug'
require 'minitest/autorun'  # unit and spec
root = File.expand_path('../..',File.dirname(__FILE__))
require "#{root}/lib/parsie.rb"
require "#{root}/test/support/helpers.rb"
