# frozen_string_literal: true

require_relative '../lib/lalrrb'

# A tiny-C parser adapted from https://gist.github.com/KartikTalwar/3095780
class TinyC < Lalrrb::Grammar
  token(:IF, 'if')
  token(:ELSE, 'else')
  token(:WHILE, 'while')
  token(:DO, 'do')
  token(:ID, /[A-Za-z_][A-Za-z_0-9]*/)
  token(:UINT, /0|[1-9][0-9]*/)
  token(:WSP, /[ \t\r\n]/) { toss }

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
  done
end

TEST_CODE = %(
  {
    i = 7;
    if (i < 5) x = 1;
    if (i < 10) y = 2;
  }
)

TinyC.syntax_diagram.save('tiny-c-syntax-diagram.svg')

parser = Lalrrb::Parser.new(TinyC)
parser.productions.each { |p| puts p }
puts parser.nff_table.to_s(uniform_widths: false)
puts parser.table.to_s(uniform_widths: false)

puts parser.parse(TEST_CODE).to_s(uniform_widths: false)
