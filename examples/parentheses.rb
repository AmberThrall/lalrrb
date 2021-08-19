# frozen_string_literal: true

require_relative '../lib/lalrrb'

grammar = Lalrrb::BasicGrammar.new
grammar.start = :S
grammar.add_production(:S, :S, :S)
grammar.add_production(:S, '(', ')')
grammar.add_production(:S, '(', :S, ')')
grammar.add_production(:S, '[', ']')
grammar.add_production(:S, '[', :S, ']')

parser = Lalrrb::Parser.new(grammar)
puts parser.grammar
parser.states.each_with_index { |s, i| puts "#{i}:"; puts s }
parser.table.pretty_print

tree, log = parser.parse("([[[()()[][]]]([])])")
log.pretty_print
tree.graphviz.output(png: "parentheses.png")
