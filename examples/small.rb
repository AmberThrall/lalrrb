# frozen_string_literal: true

require_relative '../lib/lalrrb'

grammar = Lalrrb::BasicGrammar.new
grammar.lexer.token(:c, 'c')
grammar.lexer.token(:d, 'd')
grammar.start = :S
grammar.add_production(:S, :E, :E)
grammar.add_production(:E, :C)
grammar.add_production(:C, :c, :C)
grammar.add_production(:C, :d)

parser = Lalrrb::Parser.new(grammar)
puts parser.grammar
parser.grammar.nff.pretty_print
parser.states.each_with_index { |s, i| puts "#{i}:"; puts s }
parser.table.pretty_print

tree, log = parser.parse("cdcd")
log.pretty_print
tree.graphviz.output(png: "small.png")
