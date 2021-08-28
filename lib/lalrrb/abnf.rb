# frozen_string_literal: true

require_relative 'grammar'
require_relative 'parser'

module Lalrrb
  module Grammars
    class ABNF
      class Grammar < Lalrrb::Grammar
        token(:CRLF, "\r\n")
        token(:DIGIT, /[0-9]/)
        token(:RULENAME, /[A-Za-z_][A-Za-z0-9_-]*/)
        token(:COMMENT, /;.*\r\n/)
        token(:CHAR_VAL, /"(?:\\u[0-9A-Fa-f]{4}|\\.|[^"\\\r\n])*"/)
        #token(:REGEXP_VAL, /\/(?:\\u[0-9A-Fa-f]{4}|\\.|[^\/\\\r\n])*\//)
        token(:BIN_VAL, /%b[01]+(?:(?:\.[01]+)+|-[01]+)?/)
        token(:DEC_VAL, /%d[0-9]+(?:(?:\.[0-9]+)+|-[0-9]+)?/)
        token(:HEX_VAL, /%x[0-9A-Fa-f]+(?:(?:\.[0-9A-Fa-f]+)+|-[0-9A-Fa-f]+)?/)
        #token(:PROSE_VAL, /<[\u0020-\u003D\u003F-\u007E]>/)
        ignore(/[ \t]/)

        start(:rulelist)
        rule(:rulelist) { (command / rule / c_nl).repeat }
        rule(:command) { '%' >> (token / ignore / start) }
        rule(:token) { "token" >> '(' >> RULENAME >> ',' >> token_value >> ')' >> c_nl }
        rule(:ignore) { "ignore" >> '(' >> token_value >> ')' >> c_nl }
        rule(:token_value) { value >> ('/' >> value).repeat }
        rule(:start) { "start" >> '(' >> RULENAME >> ')' >> c_nl }
        rule(:rule) { RULENAME >> defined_as >> alternation >> c_nl }
        rule(:defined_as) { '=' / '=/' }
        rule(:c_nl) { COMMENT / CRLF }
        rule(:alternation) { concatenation >> ('/' >> concatenation).repeat }
        rule(:concatenation) { repetition.repeat(1) }
        rule(:repetition) { repeat? >> element }
        rule(:repeat) { DIGIT.repeat(1) / (DIGIT.repeat >> '*' >> DIGIT.repeat) }
        rule(:element) { group / option / value }
        rule(:value) { RULENAME / CHAR_VAL / BIN_VAL / DEC_VAL / HEX_VAL } # / PROSE_VAL }
        rule(:group) { '(' >> alternation >> ')' }
        rule(:option) { '[' >> alternation >> ']' }
      end

      def self.parse(text)
        Grammar.syntax_diagram.save('abnf-syntax-diagram.svg')
        @parser ||= Parser.new(Grammar)
        puts @parser.grammar
        @parser.table.save("abnf.csv")
        lines = text.lines.map(&:rstrip)
        lines.delete_if { |l| l.empty? }
        offset = lines.map { |l| l.length - l.lstrip.length }.min
        lines = lines.map { |l| l[offset..] }
        text = lines.join("\r\n")
        text += "\r\n"

        @parser.parse(text, raise_on_error: false, return_steps: true)
      end
    end
  end
end
