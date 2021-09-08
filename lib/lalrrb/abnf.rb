# frozen_string_literal: true

require_relative 'grammar'
require_relative 'basic_grammar'
require_relative 'parser'

module Lalrrb
  class ABNF
    class Grammar < Lalrrb::Grammar
      token(:CRLF, "\r\n")
      token(:DIGIT, /[0-9]/)
      token(:RULENAME, /[A-Za-z_][A-Za-z0-9_-]*/)
      token(:COMMENT, /;.*\r\n/)
      token(:CHAR_VAL, /"(?:\\.|[^"\\\r\n])*"/) { |value| value.undump }
      token(:CHAR_VAL2, /'(?:\\.|[^'\\\r\n])*'/) { |value| value.gsub('\'','"').undump }
      token(:REGEXP_VAL, /%r\/(?:\\.|[^\/\\\r\n])*\/[A-Za-z]*/)
      token(:BIN_VAL, /%b[01]+(?:(?:\.[01]+)+|-[01]+)?/)
      token(:DEC_VAL, /%d[0-9]+(?:(?:\.[0-9]+)+|-[0-9]+)?/)
      token(:HEX_VAL, /%x[0-9A-Fa-f]+(?:(?:\.[0-9A-Fa-f]+)+|-[0-9A-Fa-f]+)?/)
      #token(:PROSE_VAL, /<[\u0020-\u003D\u003F-\u007E]>/)
      ignore([" ", "\t"])

      start(:rulelist)
      rule(:rulelist) { (command / rule / c_nl).repeat }
      rule(:command) { token / ignore / start }
      rule(:token) { "%token" >> '(' >> RULENAME >> ',' >> token_value >> ')' >> c_nl }
      rule(:ignore) { "%ignore" >> '(' >> token_value >> ')' >> c_nl }
      rule(:start) { "%start" >> '(' >> RULENAME >> ')' >> c_nl }
      rule(:token_value) { value >> ('/' >> value).repeat }

      rule(:rule) { RULENAME >> defined_as >> alternation >> c_nl }
      rule(:defined_as) { '=' / '=/' }
      rule(:c_nl) { COMMENT / CRLF }
      rule(:alternation) { concatenation >> ('/' >> concatenation).repeat }
      rule(:concatenation) { repetition.repeat(1) }
      rule(:repetition) { repeat? >> element }
      rule(:repeat) { DIGIT.repeat(1) / (DIGIT.repeat >> '*' >> DIGIT.repeat) }
      rule(:element) { group / option / value }
      rule(:value) { RULENAME / CHAR_VAL / REGEXP_VAL / BIN_VAL / DEC_VAL / HEX_VAL } # / PROSE_VAL }
      rule(:group) { '(' >> alternation >> ')' }
      rule(:option) { '[' >> alternation >> ']' }
    end

    def self.parse(text)
      @parser ||= Parser.new(Grammar)

      lines = text.lines.map(&:rstrip)
      # lines.delete_if { |l| l.empty? }
      # offset = lines.map { |l| l.length - l.lstrip.length }.min
      # lines = lines.map { |l| l[offset..] }
      text = lines.join("\r\n")
      text += "\r\n"

      new(@parser.parse(text)).g
    end

    attr_reader :g

    private

    def initialize(root)
      @g = Class.new(Lalrrb::Grammar)
      @rules = {}
      root.search(:command).each { |node| parse_command(node) }
      root.search(:rule).each { |node| parse_rule(node) }

      @rules.each { |name, rhs| @g.rule(name) { rhs } }
    end

    def parse_rule(node)
      name = node[:RULENAME].value.to_sym
      raise Error, "Rule '#{name}' already defined" if node[:defined_as].value == '=' && @rules.include?(name)
      raise Error, "No such rule '#{name}' to add production" if node[:defined_as].value == '=/' && !@rules.include?(name)

      rhs = parse_alternation(node[:alternation])
      if node[:defined_as].value == '=/'
        old = @rules[name].is_a?(Alternation) ? @rules[name].children : [@rules[name]]
        new = rhs.is_a?(Alternation) ? rhs.children : [rhs]
        @rules[name] = Alternation.new(*old, *new)
      else
        @rules[name] = rhs
      end
    end

    def parse_alternation(node)
      alts = Array(node[:concatenation]).map { |n| parse_concatenation(n) }
      alts.length > 1 ? Alternation.new(alts) : alts.first
    end

    def parse_concatenation(node)
      parts = Array(node[:repetition]).map { |n| parse_repetition(n) }
      parts.length > 1 ? Concatenation.new(parts) : parts.first
    end

    def parse_repetition(node)
      element = node[:element][0]

      element = case element.name
                when :RULENAME then element.value
                when :group then parse_alternation(element[:alternation])
                when :option then Optional.new(parse_alternation(element[:alternation]))
                when :value then parse_value(element)
                end

      return element if node[:repeat].nil?

      repeat = node[:repeat].value
      parts = repeat.partition('*')
      min = parts[0].empty? ? 0 : parts[0].to_i
      max = parts[2].empty? ? Float::INFINITY : parts[2].to_i
      max = min unless repeat.include?('*')

      Repeat.new(element, min, max)
    end

    def parse_command(node)
      node = node[0]

      case node.name
      when :start then @g.start(node[:RULENAME].value.to_sym)
      when :token then @g.token(node[:RULENAME].value.to_sym, parse_token_value(node[:token_value]))
      when :ignore then @g.ignore(parse_token_value(node[:token_value]))
      end
    end

    def parse_token_value(node)
      values = node.search(:value).map do |v|
        value = parse_value(v)
        raise Error, "Unknown token '#{token}'" if value.is_a?(Rule)
        raise Error, "Invalid token value '#{value}'" unless value.is_a?(Terminal)

        value.match
      end.flatten
      values.length > 1 ? values : values.first
    end

    def parse_value(node)
      node = node[0]

      case node.name
      when :RULENAME
        name = node.value.to_sym
        @g.tokens.include?(name) ? Terminal.new(@g.tokens[name][:match], name: name) : Rule.new(name)
      when :CHAR_VAL, :CHAR_VAL2 then Terminal.new(node.value)
      when :REGEXP_VAL
        f = node.value.rindex('/')
        options = node.value[f + 1..]
        o = 0
        options.split('').each do |c|
          case c
          when 'i' then o |= Regexp::IGNORECASE
          when 'm' then o |= Regexp::MULTILINE
          when 'x' then o |= Regexp::EXTENDED
          else raise Error, "Unsupported option #{c} in regular expression."
          end
        end
        Terminal.new(Regexp.new(node.value[3..f - 1], o))
      when :BIN_VAL, :DEC_VAL, :HEX_VAL
        base = { BIN_VAL: 2, DEC_VAL: 10, HEX_VAL: 16 }
        base = base[node.name]
        value = node.value[2..]

        ret = if value.include?('-')
          parts = value.partition('-')
          min = parts[0].to_i(base).chr(Encoding::UTF_8)
          max = parts[2].to_i(base).chr(Encoding::UTF_8)
          begin
            Regexp.new("[#{Regexp.escape(min)}-#{Regexp.escape(max)}]")
          rescue RegexpError
            raise Error, "Invalid range `#{node.value}'."
          end
        else
          value.split('.').map { |x| x = x.to_i(base).chr(Encoding::UTF_8) }.join
        end

        Terminal.new(ret)
      end
    end
  end
end
