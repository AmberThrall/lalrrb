require_relative '../lib/lalrrb'

class Expr < Lalrrb::Grammar
  token(:FLOAT, /[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/)
  token(:OCTAL, /0o[0-7]+/)
  token(:HEX, /0x[0-9A-Fa-f]+/)
  token(:SP, /[ \t]+/) { toss }
  token(:NEWLINE, /\r?\n/) { toss }

  start(:expr)
  rule(:expr) { sum }
  rule(:sum) { (sum >> '+' >> product) / (sum >> '-' >> product) / product }
  rule(:product) { (product >> '*' >> term) / (product >> '/' >> term) / term }
  rule(:term) { ('(' >> expr >> ')') / number }
  rule(:number) { OCTAL / HEX / FLOAT }
  done
end

Expr.syntax_diagram().save('expr-syntax-diagram.svg')

parser = Lalrrb::Parser.new(Expr)
parser.grammar.productions.each { |p| puts p }
parser.table.pretty_print
tree, log = parser.parse("26 + (3.14 * 0xbeef)")
log.pretty_print
tree.graphviz.output(png: "expr.png")
