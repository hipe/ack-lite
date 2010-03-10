require 'minitest/autorun'  # unit and spec
require 'ruby-debug'

root =  File.dirname(__FILE__)
require "#{root}/table.rb"
require "#{root}/tokenizer.rb"
require "#{root}/string.rb"
require "#{root}/regexp.rb"
require "#{root}/hookey.rb"
require "#{root}/union-basic.rb"
require "#{root}/concat-basic.rb"
require "#{root}/structured-basic.rb"
require "#{root}/left-recursion-basic.rb"
require "#{root}/left-recursion-page-45.rb"
