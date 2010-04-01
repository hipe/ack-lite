root = File.expand_path('../parsie',__FILE__)
require root + '/general-support.rb'
require root + '/table-and-tokenizer.rb'
require root + '/productions.rb'
require root + '/parse-support.rb'
require root + '/terminal-parsers.rb'
require root + '/nonterminal-parsers.rb'
require root + '/recursive-reference.rb'

# note1 - UnionSymbols are only ever created by the table, pipe operator not
#         supported
# note2 - union symbols are only constructed in this one place
# note9 - if we wanted to get really cracked out we would deal with
#         handling multiple interested children in the running in concats.
#         but for now, such scenarios should be built into unions not concats.
# note10 - recursive references are collapsed very late, might cause problems