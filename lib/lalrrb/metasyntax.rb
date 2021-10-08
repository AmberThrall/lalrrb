# frozen_string_literal: true

require_relative 'grammar'
require_relative 'parser'

module Lalrrb
  class Metasyntax
    class Grammar < Lalrrb::Grammar
      token(:TOKEN, "token")
      token(:FRAGMENT, "fragment")
      token(:OPTIONS, "options")
      token(:TRUE_VAL, "true")
      token(:FALSE_VAL, "false")
      token(:NIL_VAL, "nil")
      token(:LPAREN, "(")
      token(:RPAREN, ")")
      token(:COMMA, ",")
      token(:COLON, ":")
      token(:SEMI, ";")
      token(:OR, "|")
      token(:PLUS, "+")
      token(:STAR, "*")
      token(:QUESTION, "?")
      token(:DOT, ".")
      token(:ARROW, "->")
      token(:DOTDOT, "..")
      token(:ESCAPE, /\\./)
      token(:LBRACE, "{")
      token(:RBRACE, "}")
      token(:ASSIGN, "=")
      token(:NUMBER, /-?\d+(\.\d+)?([eE][+-]?\d+)?/) { |value| value.to_i == value.to_f ? value.to_i : value.to_f }
      token(:IDENTIFIER, /[A-Za-z_][A-Za-z0-9_]*/) { |value| value.to_sym }
      token(:CHAR_VAL, /"(\\.|[^"\\\r\n])*"|'(\\.|[^'\\\r\n])*'/) do |value|
        "\"#{value[1..-2].gsub('"', "\\\"").gsub("\\'", "'")}\"".undump
      end
      token(:BLOCK_VAL, /\[(\\.|[^\\\r\n\[\]])+\]/)
      token(:REGEXP_VAL, /\/(\\.|[^\/\\\r\n\*])(\\.|[^\/\\\r\n])*\//)
      token(:WSP, [" ", "\t", "\f", "\r", "\n"], skip: true)
      token(:COMMENT, /\/\/.*\r?\n/, skip: true)
      token(:COMMENT_BLOCK, /\/\*(\*[^\/]|[^\*])*\*\//, skip: true)

      start(:rulelist)
      rule(:rulelist) { (options | rule).repeat }
      rule(:options) { OPTIONS >> LBRACE >> option.repeat >> RBRACE }
      rule(:option) { IDENTIFIER >> ASSIGN >> option_value >> SEMI }
      rule(:option_value) do
        IDENTIFIER | CHAR_VAL | NUMBER | TRUE_VAL | FALSE_VAL | NIL_VAL
      end
      rule(:rule) do
        rule_prefix? >> IDENTIFIER >> COLON >> alternation? >> rule_commands? >> SEMI
      end
      rule(:rule_prefix) { TOKEN | (TOKEN >> LPAREN >> IDENTIFIER >> RPAREN) | FRAGMENT }
      rule(:rule_commands) { ARROW >> rule_command >> (COMMA >> rule_command).repeat }
      rule(:rule_command) do
        IDENTIFIER |
          (IDENTIFIER >> LPAREN >> RPAREN) |
          (IDENTIFIER >> LPAREN >> option_value >> (COMMA >> option_value).repeat >> RPAREN)
      end
      rule(:alternation) { concatenation >> (OR >> concatenation?).repeat }
      rule(:concatenation) { element.repeat(1) }
      rule(:element) { value >> suffix? }
      rule(:suffix) { (repeat | QUESTION) >> QUESTION? }
      rule(:repeat) { PLUS | STAR | (LBRACE >> NUMBER >> RBRACE) | (LBRACE >> NUMBER >> COMMA >> NUMBER? >> RBRACE) }
      rule(:value) do
        group | IDENTIFIER | CHAR_VAL | ESCAPE | BLOCK_VAL | DOT | REGEXP_VAL | range
      end
      rule(:group) { LPAREN >> alternation >> RPAREN }
      rule(:range) { CHAR_VAL >> DOTDOT >> CHAR_VAL }
    end

    def self.parse(text)
      @parser ||= Parser.new(Grammar)

      new(@parser.parse(text)).g
    end

    attr_reader :g

    private

    COMMANDS = {
      TOKEN: {
        skip: [0], more: [0], insensitive: [0], to_f: [0], to_sym: [0], to_c: [0], to_r: [0],
        push_mode: [1], pop_mode: [0], mode: [1],
        to_i: [0, 1]
      },
      FRAGMENT: {},
      RULE: {}
    }.freeze

    def initialize(root)
      @g = Class.new(Lalrrb::Grammar)
      @rules = {}
      @options = {}
      root.search(:options).each { |node| Array(node[:option]).each { |n| parse_option(n) } }
      root.search(:rule).each { |node| parse_rule(node) }

      @rules.each do |name, data|
        adjective = data[:prefix].to_s.downcase
        data[:commands].each do |cmd, args|
          if COMMANDS[data[:prefix]].include?(cmd)
            expected = COMMANDS[data[:prefix]][cmd]
            expected = expected.length == 1 ? expected.first : "#{expected[..-2].join(", ")} or #{expected[-1]}"

            raise Error, "#{data[:pos]}: wrong number of arguments in command `#{cmd}' for #{adjective} `#{name}' (given #{args.length}, expected #{expected})" unless COMMANDS[data[:prefix]][cmd].include?(args.length)
          else
            raise Error, "#{data[:pos]}: undefined command `#{cmd}' for #{adjective} `#{name}'"
          end
        end

        case data[:prefix]
        when :TOKEN
          flags = {}
          [:skip, :more, :insensitive].each { |cmd| flags[cmd] = true if data[:commands].include?(cmd) }
          flags[:mode] = data[:mode]

          @g.token(name, replace_rules(data[:rhs]).to_regex, **flags) do |value|
            data[:commands].each do |cmd, args|
              case cmd
              when :push_mode then push_mode(args[0])
              when :pop_mode then pop_mode()
              when :mode then mode(args[0])
              when :to_i then value = value.to_s.to_i(*args)
              when :to_f then value = value.to_s.to_f
              when :to_sym then value = value.to_s.to_sym
              when :to_c then value = value.to_s.to_c
              when :to_r then value = value.to_s.to_r
              end
            end

            value
          end
        when :FRAGMENT then # skip
        when :RULE
          rhs = replace_rules(data[:rhs])
          @g.rule(name) { rhs }
        end
      end

      @options.each { |name, value| @g.set_option(name, value) }
    end

    def replace_rules(nonterminal)
      nonterminal.children = nonterminal.children.map do |c|
        if c.is_a?(Rule)
          name = c.name.to_sym
          if name == :EOF
            Grammar::EOF
          else
            raise Error, "unknown rule `#{name}'" unless @rules.include?(name)

            case @rules[name][:prefix]
            when :TOKEN then Terminal.new(replace_rules(@rules[name][:rhs]).to_regex, name: name)
            when :FRAGMENT then replace_rules(@rules[name][:rhs])
            when :RULE then @g.rules.include?(name) ? @g.rules[name] : Rule.new(name) { @rules[name][:rhs] }
            end
          end
        else
          replace_rules(c)
        end
      end

      nonterminal
    end

    def parse_rule(node)
      name = node[:IDENTIFIER].value
      raise Error, "production `#{name}' already defined at #{@rules[name][:pos]}" if @rules.include?(name)

      rhs = node[:alternation].nil? ? Grammar::EPSILON : parse_alternation(node[:alternation])

      cmds = {}
      unless node[:rule_commands].nil?
        Array(node[:rule_commands][:rule_command]).each do |n|
          id = n[:IDENTIFIER].value
          cmds[id] = Array(n[:option_value]).map { |v| parse_option_value(v) }
        end
      end

      prefix = node[:rule_prefix].nil? ? :RULE : node[:rule_prefix][0].name
      mode = (prefix == :TOKEN && !node[:rule_prefix][:IDENTIFIER].nil? ? node[:rule_prefix][:IDENTIFIER].value : :default)
      @rules[name] = { pos: node.position, rhs: rhs, prefix: prefix, mode: mode, commands: cmds }
    end

    def parse_alternation(node)
      alts = []
      alt = Grammar::EPSILON
      node.children.each do |n|
        case n.name
        when :concatenation then alt = parse_concatenation(n)
        when :OR
          alts << alt
          alt = Grammar::EPSILON
        end
      end
      alts << alt

      alts.length > 1 ? Alternation.new(alts) : alts.first
    end

    def parse_concatenation(node)
      parts = Array(node[:element]).map { |n| parse_element(n) }
      parts.length > 1 ? Concatenation.new(parts) : parts.first
    end

    def parse_element(node)
      element = parse_value(node[:value])

      suffix = node[:suffix]
      unless suffix.nil?
        if suffix[0].name == :repeat
          case suffix[0][0].name
          when :PLUS then element = Repeat.new(element, 1)
          when :STAR then element = Repeat.new(element)
          when :LBRACE
            nums = Array(suffix[0][:NUMBER]).map { |n| n.value.to_i }
            nums << (suffix[0][:COMMA].nil? ? nums[0] : Float::INFINITY) if nums.length == 1
            raise Error, "#{suffix[0].position}: invalid repeat suffix `#{suffix[0].value}'." if nums[0] > nums[1]

            element = Repeat.new(element, nums[0], nums[1])
          end
        end
        element = Optional.new(element) unless suffix[:QUESTION].nil?
      end

      element
    end

    def parse_option(node)
      name = node[:IDENTIFIER].value
      value = parse_option_value(node[:option_value])
      @options[name] = value
    end

    def parse_option_value(node)
      node = node[0]

      case node.name
      when :IDENTIFIER, :CHAR_VAL, :NUMBER then node.value
      when :TRUE_VAL then true
      when :FALSE_VAL then false
      when :NIL_VAL then nil
      end
    end

    def parse_value(node)
      node = node[0]

      case node.name
      when :group then parse_alternation(node[:alternation])
      when :IDENTIFIER then Rule.new(node.value)
      when :CHAR_VAL then Terminal.new(node.value)
      when :ESCAPE, :BLOCK_VAL, :DOT
        begin
          Terminal.new(Regexp.new(node.value))
        rescue RegexpError
          raise Error, "#{node.position}: invalid regular expression `#{node.value}'"
        end
      when :REGEXP_VAL
        begin
          Terminal.new(Regexp.new(node.value[1..-2]))
        rescue RegexpError
          raise Error, "#{node.position}: invalid regular expression `#{node.value}'"
        end
      when :range
        min = node[0].value
        max = node[2].value
        begin
          Terminal.new(Regexp.new("[#{Regexp.escape(min)}-#{Regexp.escape(max)}]"))
        rescue RegexpError
          raise Error, "#{node.position}: invalid range `#{node.value}'"
        end
      end
    end
  end
end
