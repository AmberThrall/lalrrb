# frozen_string_literal: true

require_relative '../lib/lalrrb'

grammar = Lalrrb::BasicGrammar.new
grammar.start = :S
grammar.add_production(:S, :E, :E)
grammar.add_production(:E, :C)
grammar.add_production(:C, 'c', :C)
grammar.add_production(:C, 'd')

parser = Lalrrb::Parser.new(grammar)
puts parser.grammar
parser.grammar.nff.pretty_print
parser.states.each_with_index { |s, i| puts "#{i}:"; puts s }
parser.table.pretty_print

root, steps = parser.parse("cdcd", return_steps: true)
steps.pretty_print
root.graphviz.output(png: "small.png")
