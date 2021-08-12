require_relative '../lib/lalrrb'

class Expr < Lalrrb::Grammar
  token(:DIGIT, /[0-9]/)
  token(:OCTAL, /[0-7]/)
  token(:HEXDIGIT, /[0-9A-Fa-f]/)
  token(:LETTER, /[A-Za-z]/)
  token(:SP, /[ \t]+/) { toss }
  token(:NEWLINE, /\r?\n/) { toss }

  start(:expression)
  rule(:expression) { term >> (('+' / '-') >> expression).optional }
  rule(:term) { factor >> (('*' / '/') >> term).optional }
  rule(:factor) { number / variable / ('(' >> expression >> ')') }
  rule(:number) { octal / hex / ('-'.optional >> DIGIT.repeat(1) >> ('.' >> DIGIT.repeat(1)).optional >> exponent?) }
  rule(:exponent) { ('e' / 'E') >> ('+' / '-').optional >> DIGIT.repeat(1) }
  rule(:octal) { '0o' >> OCTAL.repeat(1) }
  rule(:hex) { '0x' >> HEXDIGIT.repeat(1) }
  rule(:variable) { (LETTER / '_') >> (LETTER / DIGIT / '_').repeat }
  done
end

p Expr.tokens
p Expr.lexer.tokenize("52 * (3.14 + 13)").map(&:to_s)
puts Expr.to_s
pp Expr.to_h
Expr.syntax_diagram().save('expr-syntax-diagram.svg')
