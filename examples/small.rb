# frozen_string_literal: true

require_relative '../lib/lalrrb'

grammar = Lalrrb::BasicGrammar.new
grammar.start = :S
grammar.add_production(:S, :C, :C)
grammar.add_production(:C, 'c', :C)
grammar.add_production(:C, 'd')

parser = Lalrrb::Parser.new(grammar)
puts parser.grammar
puts parser.nff_table
parser.states.each_with_index { |s, i| puts "#{i}:"; puts s }
puts parser.table

puts parser.parse("cdcd").to_s(uniform_widths: false)
