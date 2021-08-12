# frozen_string_literal: true

require_relative '../lib/lalrrb'

class Small < Lalrrb::Grammar
  start(:s)
  rule(:s) { ('(' >> l >> ')') / 'x' }
  rule(:l) { s / (l >> ',' >> s) }
  done
end

puts Small.to_s
Small.syntax_diagram.save('small-syntax-diagram.svg')

parser = Lalrrb::Parser.new(Small)
parser.productions.each { |p| puts p }
