# frozen_string_literal: true

require 'lalrrb'

TinyC = Lalrrb.create(%(
  /**
   * A grammar for the language Tiny-C.
   *
   * Modified from: https://gist.github.com/KartikTalwar/3095780
   */

  // Tokens
  token ID : "a".."z" -> to_sym ;
  token INT : "-"? [0-9]+ -> to_i ;
  token HEX : "0x" [0-9A-Fa-f]+ -> to_i(16) ;
  /* C-Style comments */
  token COMMENT_START : "/*" -> skip, push_mode(COMMENT) ;
  token(COMMENT) COMMENT_TEXT : ("*" [^/]|[^*])+ -> skip ;
  token(COMMENT) COMMENT_END : "*/" -> skip, pop_mode ;
  /* Whitespace */
  token WSP
    : " "
    | "\\t"
    | "\\r"
    | "\\n"
    | "\\f"
    -> skip ;

  // Actual rule definitions
  program : statement ;
  statement
    : "if" paren_expr statement
    | "if" paren_expr statement "else" statement
    | "while" paren_expr statement
    | "do" statement "while" paren_expr ";"
    | "{" statement* "}"
    | "print" paren_expr ";"
    | expr ";"
    | ";"
    ;
  paren_expr : "(" expr ")" ;
  expr : ID "=" expr | test ;
  test : sum "<" sum | sum ;
  sum : sum ("+" | "-") term | term ;
  term
    : ID
    | INT
    | HEX
    | paren_expr
    ;
), benchmark: true, start: :program)

puts TinyC::Grammar
TinyC::Grammar.syntax_diagram.save('tiny-c-syntax-diagram.svg')

def exec(node)
  case node.name
  when :program
    @variables = {}
    exec(node[:statement])
  when :statement
    case node[0].name
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
    when "print" then puts exec(node[:paren_expr])
    when :expr then exec(node[:expr])
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
  when :term then exec(node[0])
  when :ID
    raise StandardError, "Unknown variable `#{node.value}'" unless @variables.include?(node.value)

    @variables[node.value]
  when :INT, :HEX then node.value
  end
end

exec(TinyC.parse(%(
  {
    /* Compute the 10th fibonnaci number. */
    a = 1;
    b = 2;
    n = 3;

    while (n < 0xA) {
      b = a + b;
      a = b - a;
      n = n + 1;
    }

    print(b);
  }
)))
