# frozen_string_literal: true

require_relative '../lib/lalrrb'

# A tiny-C parser adapted from https://gist.github.com/KartikTalwar/3095780
Lalrrb.create(:TinyC, %(
    %token(ID, %x61-7A) ; a-z
    %token(INT, %r/-?\\d+/)
    %token(HEX, %r/0x[\\dA-Fa-f]+/)
    %ignore(%r/\\/\\*.*\\*\\//m) ; C-style comments.
    %ignore(" " / "\\t" / "\\r" / "\\n")
    %start(program)

    program = statement

    statement =  "if" paren_expr statement
    statement =/ "if" paren_expr statement "else" statement
    statement =/ "while" paren_expr statement
    statement =/ "do" statement "while" paren_expr ";"
    statement =/ "{" *statement "}"
    statement =/ expr ";"
    statement =/ ";"

    paren_expr = "(" expr ")"
    expr = ID "=" expr / test
    test = sum "<" sum / sum
    sum = sum ("+" / "-") term / term
    term = ID / INT / HEX / paren_expr
))

TinyC.grammar.syntax_diagram.save('tiny-c-syntax-diagram.svg')

def exec(node)
  case node.name
  when :program then exec(node[:statement])
  when :statement
    case node[0].value
    when "if"
      if exec(node[1])
        exec(node[2])
      elsif node.degree == 5
        exec(node[4])
      end
    when "while"
      exec(node[:statement]) while exec(node[:paren_expr])
    when "do"
      exec(node[:statement])
      exec(node[:statement]) while exec(node[:paren_expr])
    when "{" then Array(node[:statement]).each { |n| exec(n) }
    when ";" then nil
    else exec(node[:expr])
    end
  when :paren_expr then exec(node[:expr])
  when :expr
    return exec(node[:test]) unless node[:test].nil?

    @variables[node[:ID].value] = exec(node[:expr])
  when :test, :sum
    return exec(node[0]) if node.degree == 1

    lhs = exec(node[0])
    rhs = exec(node[2])
    case node[1].value
    when "<" then lhs < rhs
    when "+" then lhs + rhs
    when "-" then lhs - rhs
    end
  when :term
    case node[0].name
    when :ID
      raise StandardError, "Unknown variable '#{node[0].value}'" unless @variables.include?(node[0].value)

      @variables[node[0].value]
    when :INT then node[0].value.to_i
    when :HEX then node[0].value[2..].to_i(16)
    when :paren_expr then exec(node[0])
    end
  end
end

root = TinyC.parse(%(
  {
    /* Compute the 10th fibonnaci number. */
    a = 1;
    b = 2;
    n = 3;

    while (n < 10) {
      b = a + b;
      a = b - a;
      n = n + 1;
    }
  }
))
root.graphviz.output(png: "tiny-c.png")

@variables = {}
exec(root)
@variables.each { |k,v| puts "#{k} = #{v}" }
