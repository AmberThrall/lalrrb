require_relative '../lib/lalrrb'

class Expr < Lalrrb::Grammar
  token(:SP, /[ \t]+/) { toss }
  token(:NEWLINE, /\r?\n/) { toss }

  start(:expr)
  rule(:expr) { sum }
  rule(:sum) { (sum >> '+' >> product) / (sum >> '-' >> product) / product }
  rule(:product) { (product >> '*' >> term) / (product >> '/' >> term) / term }
  rule(:term) { ('(' >> expr >> ')') / number / variable }
  rule(:number) { octal / hex / (digit.repeat(1) >> ('.' >> digit.repeat(1)).optional) }
  rule(:octal) { '0o' >> octal_digit.repeat(1) }
  rule(:hex) { '0x' >> hex_digit.repeat(1) }
  rule(:variable) { (letter / '_') >> (letter / '_' / digit).repeat }
  rule(:octal_digit) { '0' / '1' / '2' / '3' / '4' / '5' / '6' / '7' }
  rule(:digit) { octal_digit / '8' / '9' }
  rule(:hex_digit) { digit / 'a' / 'b' / 'c' / 'd' / 'e' / 'f' / 'A' / 'B' / 'C' / 'D' / 'E' / 'F' }
  rule(:letter) do
    alt = 'a' / 'A'
    ('b'..'z').each { |c| alt /= c; alt /= c.upcase }
    alt
  end
  done
end

Expr.syntax_diagram().save('expr-syntax-diagram.svg')

parser = Lalrrb::Parser.new(Expr)
parser.productions.each { |p| puts p }
puts parser.parse("26 + 3.14 * 0xbeef / var").save("expr.csv")
