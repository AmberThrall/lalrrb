require_relative '../lib/lalrrb'

lex = Lalrrb::Lexer.new
grammar = Lalrrb::Grammar.new

class Expr < Lalrrb::Grammar
  token(:NUMBER, /[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[1-9][0-9]*)*/)
  token(:SP, [' ', '\t']) { toss }

  start(:expression)
  rule(:expression) { (expression >> operator >> expression) / term }
  rule(:term) { ('(' >> expression >> ')') / ('-'.optional >> NUMBER) }
  rule(:operator) { '+' / '-' / '*' / '/' }
  done
end

p Expr.tokens
p Expr.lexer.tokenize("52 * (3.14 + 13)").map(&:to_s)
puts Expr.to_s
pp Expr.to_h
