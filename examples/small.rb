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
