# frozen_string_literal: true

require_relative 'terminal'
require_relative 'rule'
require_relative 'epsilon'
require_relative 'lexer'
require_relative 'basic_grammar'

module Lalrrb
  class Grammar
    EPSILON = Epsilon.new
    EOF = Terminal.new(:EOF, name: :EOF)

    def self.default_options
      @options = {
        start: rules.keys.first,
        conflict_mode: Lexer::CONFLICT_MODES.first
      }
    end

    def self.options
      default_options if @options.nil?
      @options
    end

    def self.get_option(name)
      name = name.to_sym
      default_options if @options.nil?
      raise Error, "unknown option #{name}" unless @options.include?(name)

      @options[name]
    end

    def self.set_option(name, value)
      name = name.to_sym
      default_options if @options.nil?
      raise Error, "unknown option #{name}" unless @options.include?(name)

      @options[name] = value
    end

    def self.lexer(add_terminals: true)
      default_options if @options.nil?

      @lexer ||= Lexer.new
      @lexer.conflict_mode = @options[:conflict_mode]

      # Convert terminals into tokens
      if add_terminals
        terminals = @rules.nil? ? [] : @rules.map { |_, rule| rule.search(:terminal, expand: true) }.flatten
        terminals.each do |t|
          name = t.name.nil? ? t.match : t.name
          next if @lexer.tokens.include?(name) || name == :EOF

          @lexer.token(name, t.match)
        end
      end

      @lexer
    end

    def self.tokens
      lexer.tokens
    end

    def self.instance
      @instance ||= new
      @instance
    end

    def self.rules
      @rules ||= {}
      @rules
    end

    def self.token(name, match, **flags, &block)
      name = name.to_sym
      @rules ||= {}

      raise Error, "token #{name} already defined" if lexer(add_terminals: false).tokens.include?(name) || name == :EOF
      raise Error, "token #{name} conflicts with rule #{name}" if @rules.include?(name)
      raise Error, "method #{name}? already defined" if method_defined?("#{name}?".to_sym)

      begin
        raise Error, "constant #{name} already defined" if const_defined?(name)

        lexer.token(name, match, **flags, &block)
        const_set(name, Terminal.new(match, name: name))
      rescue NameError
        raise Error, "method #{name} already defined" if method_defined?(name)

        lexer.token(name, match, **flags, &block)
        define_method(name) { Terminal.new(match, name: name) }
      end

      define_method("#{name}?".to_sym) { Optional.new(Terminal.new(match, name: name)) }
    end

    def self.rule(name, &block)
      name = name.to_sym
      @rules ||= {}

      raise Error, "rule #{name} already defined" if @rules.include?(name)
      raise Error, "rule #{name} conflicts with token #{name}" if lexer(add_terminals: false).tokens.include?(name)
      raise Error, "method #{name}? already defined" if method_defined?("#{name}?".to_sym)

      block_closure = proc { instance.instance_eval(&block) }

      begin
        raise Error, "constant #{name} already defined" if const_defined?(name)

        @rules[name] = Rule.new(name, &block_closure)
        const_set(name, rules[name])
      rescue NameError
        raise Error, "method #{name} already defined" if method_defined?(name)

        @rules[name] = Rule.new(name, &block_closure)
        define_method(name) { self.class.rules[name] }
      end

      define_method("#{name}?".to_sym) { self.class.rules[name].optional }
      start(name) if get_option(:start).nil?
    end

    def self.start(start = nil)
      return get_option(:start) if start.nil?

      set_option(:start, start.to_sym)
    end

    def nonterminal?(arg)
      @rules.include?(arg)
    end

    def terminal?(arg)
      lexer.tokens.each do |t|
        return true if t.name == arg || t.match == arg
      end
      false
    end

    def symbol?(arg)
      nonterminal?(arg) || terminal?(arg)
    end

    def self.to_basic
      # Convert to basic grammar
      bg = BasicGrammar.new(lexer: lexer)
      bg.start = get_option(:start)
      @rules.each { |_, rule| bg.add_production(rule) }
      bg
    end

    def self.to_s
      @rules ||= {}
      options_backup = @options.clone
      default_options
      options_default = @options
      @options = options_backup

      s = Hash(@options).map { |k,v| v == options_default[k] && k != :start ? "" : "% #{k} = #{v}" }.filter { |s| !s.empty? }.join("\n")
      s += "\n" unless s.empty?
      s += "% tokens:"
      lexer.tokens.each do |name, t|
        next unless name.is_a?(Symbol)
        next if name == :EOF || t[:skip]

        s += " #{name}"
      end
      s += "\n"
      s += @rules.map { |_, rule| rule.to_s(expand: true) }.join("\n")
      s
    end

    def self.to_h
      @rules ||= {}
      default_options if @options.nil?

      {
        options: @options,
        tokens: lexer.tokens,
        rules: @rules.map { |_, rule| rule.to_h(expand: true) }
      }
    end

    def self.syntax_diagram(*rules)
      rules = @rules.keys if Array(rules).empty?
      root = SVG::Root.new()
      y = 0
      rules.each do |rule|
        raise Error, "unknown rule `#{rule}' provided to syntax_diagram" unless @rules.include?(rule)

        label = get_option(:start) == rule ? "*#{rule}*:" : "#{rule}:"
        root << SVG::Text.new(label, 0, y, text_anchor: 'left', alignment_baseline: 'hanging', font_weight: 'bold')
        root << g = @rules[rule].to_svg(expand: true).move(20, y + 10)
        root.attributes[:width] = [root.attributes[:width].to_i , g.width + 40].max
        y += g.height + 50
      end
      root.attributes[:height] = y
      root
    end
  end
end
