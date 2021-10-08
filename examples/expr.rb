# frozen_string_literal: true

require 'lalrrb'

Expr = Lalrrb.create(%(
  token NUMBER : "-"? DIGITS FRACTION? EXPONENT? -> to_f ;
  fragment FRACTION : "." DIGITS ;
  fragment EXPONENT : [eE] [+-]? DIGITS ;
  fragment DIGITS : ("0".."9")+ ;
  token SP : " " | "\\t" -> skip ;
  options { start = expr; }

  expr : sum ;
  sum
    : sum ("+" | "-") product
    | product
    ;

  product
    : product ("*" | "/") power
    | power
    ;

  power
    : power "**" term
    | term
    ;

  term
    : "(" expr ")"
    | NUMBER
    ;
), benchmark: true)

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
    when "**" then lhs ** rhs
    end
  when :term then compute(node[:expr].nil? ? node[:NUMBER] : node[:expr])
  when :NUMBER then node.value
  end
end

puts Expr::Grammar

loop do
  begin
    print "> "
    prompt = gets.chomp
    break if prompt.downcase == "quit"

    root = Expr.parse(prompt)
    puts compute(root)
  rescue Lalrrb::Error => e
    warn "Syntax Error: #{e.message}"
  end
end
