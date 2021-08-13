# frozen_string_literal: true

require_relative '../lib/lalrrb'

class Small < Lalrrb::Grammar
  start(:rS)
  rule(:rS) { (rV >> '=' >> rE) / rE }
  rule(:rE) { rV }
  rule(:rV) { ('*' >> rE) / 'x' }
  done
end

parser = Lalrrb::Parser.new(Small)
parser.productions.each { |p| puts p }
puts parser.nff_table
parser.states.each_with_index { |s, i| puts "#{i}:"; puts s }
parser.graphviz.output(png: 'small-parser.png')
puts parser.table
