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
puts parser.nff_table
parser.states.each_with_index { |s, i| puts "#{i}:"; puts s }
puts parser.table

tree, log = parser.parse("([[[()()[][]]]([])])")
puts log.to_s(uniform_widths: false)
tree.graphviz.output(png: "parentheses.png")
