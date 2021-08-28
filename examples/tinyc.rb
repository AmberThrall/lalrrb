# frozen_string_literal: true

require_relative '../lib/lalrrb'

# A tiny-C parser adapted from https://gist.github.com/KartikTalwar/3095780
class TinyC < Lalrrb::Grammar
  token(:IF, 'if')
  token(:ELSE, 'else')
  token(:WHILE, 'while')
  token(:DO, 'do')
  token(:ID, /[a-z]/)
  token(:UINT, /[0-9]+/) { |value| value.to_i }
  ignore(/[ \t\r\n]/)

  start(:program)
  rule(:program) { statement }
  rule(:statement) do
    (IF >> paren_expr >> statement) /
      (IF >> paren_expr >> statement >> ELSE >> statement) /
      (WHILE >> paren_expr >> statement) /
      (DO >> statement >> WHILE >> paren_expr >> ';') /
      ('{' >> statement.repeat >> '}') /
      (expr >> ';') /
      ';'
  end
  rule(:paren_expr) { '(' >> expr >> ')' }
  rule(:expr) { test / (ID >> '=' >> expr) }
  rule(:test) { sum / (sum >> '<' >> sum) }
  rule(:sum) { term / (sum >> '+' >> term) / (sum >> '-' >> term) }
  rule(:term) { ID / UINT / paren_expr }
end

TinyC.syntax_diagram.save('tiny-c-syntax-diagram.svg')

parser = Lalrrb::Parser.new(TinyC)
puts parser.grammar
parser.grammar.nff.pretty_print
parser.table.pretty_print

root, steps = parser.parse("{ i=1; while (i<100) i=i+i; }", return_steps: true)
steps.pretty_print
root.graphviz.output(png: "tiny-c.png")
