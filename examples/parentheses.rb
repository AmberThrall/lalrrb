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
root = parser.parse("([[[()()[][]]]([])])")
root.graphviz.output(png: "parentheses.png")
