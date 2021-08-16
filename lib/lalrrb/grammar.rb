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

    def self.token(name, match, state: nil, &block)
      name = name.to_sym

      raise Error, "Token '#{name}' should be all capitalized." unless name.to_s.upcase == name.to_s
      raise Error, "Token '#{name}' already defined." if const_defined?(name)

      lexer.token(name, match, state: state, &block)
      const_set(name, Terminal.new(match, name: name))
    end

    def self.rule(name, &block)
      name = name.to_sym
      raise Error, "Rule '#{name}' already defined." if method_defined?(name) || method_defined?("#{name}?".to_sym)

      @rules ||= {}
      block_closure = proc { instance.instance_eval(&block) }
      @rules[name] = Rule.new(name, &block_closure)

      define_method(name) { self.class.rules[name] }
      define_method("#{name}?".to_sym) { self.class.rules[name].optional }
    end

    def self.start(start = nil)
      return @start if start.nil?

      @start = start.to_sym
    end

    def self.done
      # Convert terminals into tokens
      terminals = @rules.map { |_, rule| rule.search(:terminal, expand: true) }.flatten
      terminals.each do |t|
        lexer.token(t.match, t.match) unless tokens.include?(t.match)
      end
    end

    def self.to_basic
      bg = BasicGrammar.new
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
