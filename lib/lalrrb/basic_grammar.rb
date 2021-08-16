# frozen_string_literal: true

require_relative 'production'

module Lalrrb
  class BasicGrammar
    attr_accessor :start
    attr_reader :productions, :terminals, :nonterminals

    def initialize
      @productions = []
      @terminals = Set[]
      @nonterminals = Set[]
    end

    def add_production(arg0, *args)
      return convert_rule(arg0) if arg0.is_a?(Rule)

      name = arg0
      rhs = args.flatten
      @productions << Production.new(name, rhs)
      @nonterminals.add name
      @terminals.delete name
      rhs.each do |x|
        @terminals.add x unless @nonterminals.include?(x)
      end
    end

    def [](name)
      return [] if name.nil?
      return @productions[name] unless name.is_a?(String) || name.is_a?(Symbol)

      list = @productions.filter { |p| p.name == name }
      return list.first if list.length == 1

      list
    end

    def terminal?(z)
      @terminals.include? z
    end

    def nonterminal?(x)
      @nonterminals.include? x
    end

    def symbol?(x)
      terminal?(x) || nonterminal?(x)
    end

    def to_s
      s = "% start: #{@start}\n"
      s += "% terminals:"
      @terminals.each { |z| s += " #{z}" }
      @productions.each { |p| s += "\n#{p}"}
      s
    end

    def symbols
      Set[@terminals, @nonterminals].flatten
    end

    private

    def convert_rule(rule)
      p = rule.production

      if p.is_a?(Alternation)
        p.children.each { |c| add_production(rule.name, simplify(rule.name, c)) }
      else
        add_production(rule.name, simplify(rule.name, p))
      end
    end

    def simplify(rule, nonterminal)
      case nonterminal
      when Alternation
        name = unique_name("#{rule}_alternation")
        nonterminal.children.each { |c| add_production(name, simplify(name,c)) }
        name
      when Concatenation then nonterminal.children.map { |c| simplify(rule, c) }
      when Optional
        name = unique_name("#{rule}_optional")
        add_production(name, simplify(name, nonterminal.children.first))
        add_production(name)
        name
      when Repeat
        basename = unique_name("#{rule}_repeat")
        name = "#{basename}_impl".to_sym
        impl = simplify(name, nonterminal.children.first)
        name = impl if Array(impl).length == 1
        add_production(name, impl) unless Array(impl).length == 1

        case nonterminal.max
        when nonterminal.min then [name] * nonterminal.min
        when Float::INFINITY
          name_inf = "#{basename}_inf".to_sym
          add_production(name_inf, name, name_inf)
          add_production(name_inf)
          [[name] * nonterminal.min, name_inf].flatten
        else
          name_repeat = "#{basename}_repeat".to_sym
          (0..nonterminal.max - nonterminal.min).each do |i|
            add_production(name_repeat, [[name] * i].flatten)
          end
          [[name] * nonterminal.min, name_repeat].flatten
        end
      when Rule then nonterminal.name
      when Terminal then nonterminal.name.nil? ? nonterminal.match : nonterminal.name
      end
    end

    def unique_name(basename)
      i = 0
      name = basename.to_sym
      while @terminals.include?(name) || @nonterminals.include?(name)
        i += 1
        name = "#{basename}#{i}".to_sym
      end
      name
    end
  end
end
