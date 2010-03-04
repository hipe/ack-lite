root = File.expand_path(File.dirname(__FILE__))
require root + '/general-support.rb'
require root + '/table-and-tokenizer.rb'
require root + '/productions.rb'
require root + '/parse-support.rb'
require root + '/terminal-parsers.rb'
require root + '/nonterminal-parsers.rb'
# foooofoofoofoo


# note1 - UnionSymbols are only ever created by the table, pipe operator not
#  supported
# note2 - union symbols are only constructed in this one place
# note3 - this is our 'look again' algorithm
# note5 - @todo: we just skip recusive looks !?
#   the node that invokes us, self, is that forever
#   out of the running !??
#   we are forever out of the running if we are looking !??
# note6 - the whole re-evaluate thing might be better served by code blocks?
# note7 - tfpp is ridiculous - its a way to avoid recursion
# note8 - ambiguity ignored for now
