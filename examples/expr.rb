require_relative '../lib/lalrrb'
require 'bigdecimal'

Lalrrb.create(:Expr, %(
  %token(DIGIT, %x30-39)
  %ignore(" " / "\\t")
  %start(expr)

  expr = sum
  sum = sum ("+" / "-") product / product
  product = product ("*" / "/") power / power
  power = power "^" term / term
  term = "(" expr ")" / number
  number = ["-"] digits [fraction] [exponent]
  fraction = "." digits
  exponent = ("e" / "E") ["-"] digits
  digits = 1*DIGIT
))

def compute(node)
  case node.name
  when :expr then compute(node[:sum])
  when :sum, :product, :power
    return compute(node[0]) if node.degree == 1

    lhs = compute(node[0])
    rhs = compute(node[2])
    case node[1].value
    when "+" then lhs + rhs
    when "-" then lhs - rhs
    when "*" then lhs * rhs
    when "/" then lhs / rhs
    when "^" then lhs ** rhs
    end
  when :term then compute(node[:expr].nil? ? node[:number] : node[:expr])
  when :number then BigDecimal(node.value)
  end
end

puts Expr.grammar

Expr.grammar.syntax_diagram.save('expr-syntax-diagram.svg')

loop do
  begin
    print "> "
    prompt = gets.chomp
    break if prompt.downcase == "quit"

    root = Expr.parse(prompt)
    puts compute(root).to_s('F')
  rescue StandardError => e
    warn "Syntax Error: #{e.message}"
  end
end
