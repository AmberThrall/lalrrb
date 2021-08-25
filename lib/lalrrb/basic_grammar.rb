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
      @first = {}
      @recompute_first = true
    end

    def add_production(arg0, *args, generated: false)
      @recompute_first = true
      return convert_rule(arg0) if arg0.is_a?(Rule)

      name = arg0
      rhs = args.flatten
      @productions << Production.new(name, rhs, generated: generated)
      @nonterminals.add name
      @terminals.delete name
      rhs.each do |x|
        @terminals.add x unless @nonterminals.include?(x) || x.to_s.empty?
      end
    end

    def [](name)
      return [] if name.nil?
      return @productions[name] unless name.is_a?(String) || name.is_a?(Symbol) || name.is_a?(Regexp)

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

    def first(*args)
      compute_first if @recompute_first
      return @first if args.empty?

      stack = args.flatten

      set = Set[]
      stack.each do |x|
        set.add x unless symbol?(x)
        set.merge @first[x] if symbol?(x)
        break unless symbol?(x) && @first[x].include?('')
      end
      set.delete ''

      set
    end

    private

    def compute_first
      @first = {}

      # 0. first[x] = [] for all x
      symbols.each { |z| @first[z] = Set[] }

      # 1. first[z] = [z] for all terminals z
      @terminals.each { |z| @first[z].add z }

      loop do
        old = @first.clone

        # 2. For each X -> Y1Y2...Yk, do
        @productions.each do |p|
          if p.length.zero?
            @first[p.name].add ''
            next
          end

          first_false = p.rhs.map { |x| @first[x].include? '' }.find_index(false)
          first_false ||= p.length

          # 2a. if Y1, Y2, ..., Yk are nullable, then nullable[X] = true
          @first[p.name].add '' if first_false == p.length

          # 2b. first[X] = first[X] U first[Y1] U ... U first[Yj] where j is such that nullable[Yi] = true for i=1..j-1
          Array(p.rhs[0..first_false]).each do |y|
            @first[p.name].merge @first[y]
          end
        end

        break if @first == old
      end

      @recompute_first = false
    end

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
        nonterminal.children.each { |c| add_production(name, simplify(name,c), generated: true) }
        name
      when Concatenation then nonterminal.children.map { |c| simplify(rule, c) }
      when Optional
        name = unique_name("#{rule}_optional")
        add_production(name, simplify(name, nonterminal.children.first), generated: true)
        add_production(name, generated: true)
        name
      when Repeat
        basename = unique_name("#{rule}_repeat")
        name = "#{basename}_impl".to_sym
        impl = simplify(name, nonterminal.children.first)
        name = impl if Array(impl).length == 1
        add_production(name, impl, generated: true) unless Array(impl).length == 1

        case nonterminal.max
        when nonterminal.min then [name] * nonterminal.min
        when Float::INFINITY
          name_inf = "#{basename}_inf".to_sym
          add_production(name_inf, name, name_inf, generated: true)
          add_production(name_inf, generated: true)
          [[name] * nonterminal.min, name_inf].flatten
        else
          name_repeat = "#{basename}_repeat".to_sym
          (0..nonterminal.max - nonterminal.min).each do |i|
            add_production(name_repeat, [[name] * i].flatten, generated: true)
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
