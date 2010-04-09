root = File.expand_path('../parsie',__FILE__)
# order is important
require root + '/general-support.rb'
require root + '/parse-support.rb'
require root + '/looks-like.rb'
require root + '/hookey.rb'
require root + '/table.rb'
require root + '/productions.rb'
require root + '/terminal-parsers.rb'
require root + '/nonterminal-parsers.rb'
require root + '/recursive-reference.rb'
require root + '/sexpesque.rb'

# note1: - UnionSymbols are only ever created by the table, pipe operator not
#         supported
# note10: - recursive references are collapsed very late, might cause problems
