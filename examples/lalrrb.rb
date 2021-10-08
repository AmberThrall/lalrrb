# frozen_string_literal: true

require 'lalrrb'

GRAMMAR = %(
  /**
   * The grammar used by Lalrrb.grammar and Lalrrb.create
   */

  // Tokens
  token TOKEN : "token" ;
  token FRAGMENT : "fragment" ;
  token OPTIONS : "options" ;
  token TRUE_VAL : "true" ;
  token FALSE_VAL : "false" ;
  token NIL_VAL : "nil" ;
  token LPAREN : "(" ;
  token RPAREN : ")" ;
  token COMMA : "," ;
  token COLON : ":" ;
  token SEMI : ";" ;
  token OR : "|" ;
  token PLUS : "+" ;
  token STAR : "*" ;
  token QUESTION : "?" ;
  token DOT : "." ;
  token DOTDOT : ".." ;
  token ESCAPE : /\\\\./ ;
  token LBRACE : "{" ;
  token RBRACE : "}" ;
  token ASSIGN : "=" ;
  token ARROW : "->" ;
  token NUMBER : "-"? [0-9]+ ("." [0-9]+)? ([eE] [+-]? [0-9]+)? ;
  token IDENTIFIER : [A-Za-z_] [A-Za-z0-9_]* ;
  token CHAR_VAL
    : '"' /(\\\\.|[^"\\\\\\r\\n])*/ '"'
    | "'" /(\\\\.|[^'\\\\\\r\\n])*/ "'"
    ;
  token BLOCK_VAL : '[' (/\\\\./|[^\\\\\\r\\n\\[\\]])+ ']' ;
  token REGEXP_VAL : /\\/(\\\\.|[^\\/\\\\\\r\\n\\*])(\\\\.|[^\\/\\\\\\r\\n])*\\// ;
  token WSP : " " | "\\t" | "\\f" | "\\r" | "\\n" -> skip ;
  token COMMENT : /\\/\\/.*\\r?\\n/ -> skip ;
  token COMMENT_BLOCK : /\\/\\*(\\*[^\\/]|[^\\*])*\\*\\// -> skip ;

  // Starting rule
  options { start = rulelist; }

  // Rule definitions
  rulelist : (opts | rule)* ;
  opts : OPTIONS LBRACE opt* RBRACE ;
  opt : IDENTIFIER ASSIGN opt_value SEMI ;
  opt_value
    : IDENTIFIER
    | CHAR_VAL
    | NUMBER
    | TRUE_VAL
    | FALSE_VAL
    | NIL_VAL
    ;
  rule : rule_prefix? IDENTIFIER COLON alternation? rule_commands? SEMI ;
  rule_prefix
    : TOKEN
    | TOKEN LPAREN IDENTIFIER RPAREN
    | FRAGMENT
    ;
  rule_commands : ARROW rule_command (COMMA rule_command)* ;
  rule_command
    : IDENTIFIER
    | IDENTIFIER LPAREN RPAREN
    | IDENTIFIER LPAREN opt_value (COMMA opt_value)* RPAREN
    ;
  alternation : concatenation (OR concatenation?)* ;
  concatenation : element+ ;
  element : value suffix? ;
  suffix : (repeat | QUESTION) QUESTION? ;
  repeat
    : PLUS
    | STAR
    | LBRACE NUMBER RBRACE
    | LBRACE NUMBER COMMA NUMBER? RBRACE
    ;
  value
    : group
    | IDENTIFIER
    | CHAR_VAL
    | ESCAPE
    | BLOCK_VAL
    | DOT
    | REGEXP_VAL
    | range
    ;
  group : LPAREN alternation RPAREN ;
  range : CHAR_VAL DOTDOT CHAR_VAL ;
)

G = Lalrrb.create(GRAMMAR, benchmark: true)
G::Grammar.syntax_diagram.save("lalrrb.svg")
G.parse(GRAMMAR).pretty_print
