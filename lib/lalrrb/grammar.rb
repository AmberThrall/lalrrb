# frozen_string_literal: true

require_relative 'terminal'
require_relative 'rule'
require_relative 'lexer'
require_relative 'basic_grammar'

module Lalrrb
  class Grammar
    def self.lexer
      @lexer ||= Lexer.new
      @lexer
    end

    def self.tokens
      # Convert terminals into tokens
      terminals = @rules.nil? ? [] : @rules.map { |_, rule| rule.search(:terminal, expand: true) }.flatten
      terminals.each do |t|
        lexer.token(t.match, t.match)
      end

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

    def self.token(name, match, *flags, &block)
      name = name.to_sym
      @rules ||= {}
      return lexer.tokens[name] if lexer.tokens.include?(name) && match.nil? && flags.empty? && block.nil?

      raise Error, "Token #{name} already defined." if lexer.tokens.include?(name)
      raise Error, "Token #{name} conflicts with rule #{name}." if @rules.include?(name)
      raise Error, "Method #{name}? already defined." if method_defined?("#{name}?".to_sym)

      begin
        raise Error, "Constant #{name} already defined." if const_defined?(name)

        lexer.token(name, match, *flags, &block)
        const_set(name, Terminal.new(match, name: name))
      rescue NameError
        raise Error, "Method #{name} already defined." if method_defined?(name)

        lexer.token(name, match, *flags, &block)
        define_method(name) { Terminal.new(match, name: name) }
      end

      define_method("#{name}?".to_sym) { Optional.new(Terminal.new(match, name: name)) }
    end

    def self.ignore(match, *flags)
      lexer.ignore(match, *flags)
    end

    def self.rule(name, &block)
      name = name.to_sym
      @rules ||= {}
      return @rules[name] if @rules.include?(name) && block.nil?

      raise Error, "Rule #{name} already defined." if @rules.include?(name)
      raise Error, "Rule #{name} conflicts with token #{name}." if lexer.tokens.include?(name)
      raise Error, "Method #{name}? already defined." if method_defined?("#{name}?".to_sym)

      block_closure = proc { instance.instance_eval(&block) }

      begin
        raise Error, "Constant #{name} already defined." if const_defined?(name)

        @rules[name] = Rule.new(name, &block_closure)
        const_set(name, rules[name])
      rescue NameError
        raise Error, "Method #{name} already defined." if method_defined?(name)

        @rules[name] = Rule.new(name, &block_closure)
        define_method(name) { self.class.rules[name] }
      end

      define_method("#{name}?".to_sym) { self.class.rules[name].optional }
    end

    def self.start(start = nil)
      return @start if start.nil?

      @start = start.to_sym
    end

    def self.to_basic
      # Convert terminals into tokens
      terminals = @rules.map { |_, rule| rule.search(:terminal, expand: true) }.flatten
      terminals.each do |t|
        lexer.token(t.match, t.match)
      end

      # Convert to basic grammar
      bg = BasicGrammar.new(lexer: lexer)
      bg.start = @start
      @rules.each { |_, rule| bg.add_production(rule) }
      bg
    end

    def self.to_s
      @rules ||= {}
      @rules.map { |_, rule| rule.to_s(expand: true) }.join("\r\n")
    end

    def self.to_h
      @rules ||= {}
      {
        start: @start,
        rules: @rules.map { |_, rule| rule.to_h(expand: true) }
      }
    end

    def self.syntax_diagram(*rules)
      rules = @rules.keys if rules.nil? || rules.empty?
      root = SVG::Root.new()
      y = 0
      rules.each do |rule|
        root << SVG::Text.new("#{rule}:", 0, y, text_anchor: 'left', alignment_baseline: 'hanging', font_weight: 'bold')
        root << g = @rules[rule].to_svg(expand: true).move(20, y + 10)
        root.attributes[:width] = [root.attributes[:width].to_i , g.width + 40].max
        y += g.height + 50
      end
      root.attributes[:height] = y
      root
    end
  end
end
