# frozen_string_literal: true

require_relative 'production'

module Lalrrb
  class Parser
    attr_reader :productions

    def initialize(grammar)
      @grammar = grammar
      @productions = []
      @productions << Production.new(unique_name(@grammar.start, :start), @grammar.start, :EOF)
      @grammar.rules.each { |name, rule| convert_rule(rule) }
    end

    private

    def convert_rule(rule)
      p = rule.production

      if p.is_a?(Alternation)
        p.children.each { |c| @productions << Production.new(rule.name, simplify(rule.name, c)) }
      else
        @productions << Production.new(rule.name, simplify(rule.name, p))
      end
    end

    def simplify(rule, nonterminal)
      case nonterminal
      when Alternation
        name = unique_name(rule, :alternation)
        nonterminal.children.each { |c| @productions << Production.new(name, simplify(name, c)) }
        name
      when Concatenation then nonterminal.children.map { |c| simplify(rule, c) }
      when Optional
        name = unique_name(rule, :optional)
        @productions << Production.new(name, simplify(name, nonterminal.children.first))
        @productions << Production.new(name)
        name
      when Repeat
        basename = unique_name(rule, :repeat)
        name = "#{basename}_impl".to_sym
        impl = simplify(name, nonterminal.children.first)
        name = impl if Array(impl).length == 1
        @productions << Production.new(name, impl) unless Array(impl).length == 1

        case nonterminal.max
        when nonterminal.min then [name] * nonterminal.min
        when Float::INFINITY
          name_inf = "#{basename}_inf".to_sym
          @productions << Production.new(name_inf, name, name_inf)
          @productions << Production.new(name_inf, name)
          [[name] * nonterminal.min, name_inf].flatten
        else
          @productions << Production.new("#{basename}_0_#{nonterminal.min - 1}".to_sym, [name] * (nonterminal.min - 1), "#{basename}_#{nonterminal.min}".to_sym)
          (nonterminal.min..(nonterminal.max - 1)).each do |i|
            @productions << Production.new("#{basename}_#{i}".to_sym, name, "#{basename}_#{i+1}".to_sym)
            @productions << Production.new("#{basename}_#{i}".to_sym, name)
          end
          @productions << Production.new("#{basename}_#{nonterminal.max}".to_sym, name)
          @productions << Production.new("#{basename}_#{nonterminal.max}".to_sym)
          "#{basename}_0_#{nonterminal.min - 1}".to_sym
        end
      when Rule then nonterminal.name
      when Terminal then nonterminal.name.nil? ? nonterminal.match : nonterminal.name
      end
    end

    def unique_name(rule, type)
      @new_production_counts ||= {}
      @new_production_counts[type] ||= {}
      @new_production_counts[type][rule] ||= 0
      name = nil
      while name.nil? || @productions.map(&:name).include?(name) || @grammar.rules.include?(name)
        name = "#{rule}_#{type}_#{@new_production_counts[type][rule]}".to_sym
        @new_production_counts[type][rule] += 1
      end
      name
    end
  end
end
