# frozen_string_literal: true

require_relative 'production'
require_relative 'table'
require_relative 'lexer'

module Lalrrb
  class BasicGrammar
    attr_accessor :start, :lexer
    attr_reader :productions, :terminals, :nonterminals

    def initialize(lexer: nil)
      @lexer = lexer.is_a?(Lexer) ? lexer : Lexer.new
      @productions = []
      @terminals = Set[]
      @nonterminals = Set[]
      @first = {}
      @recompute_nff = true
    end

    def add_production(arg0, *args, generated: false)
      @recompute_nff = true
      return convert_rule(arg0) if arg0.is_a?(Rule)

      name = arg0
      rhs = args.flatten
      @productions << Production.new(name, rhs, generated: generated)
      @nonterminals.add name
      @terminals.delete name
      @lexer.delete_token name
      rhs.each do |x|
        @terminals.add x unless @nonterminals.include?(x) || x.to_s.empty?
        @lexer.token(x, x) unless @nonterminals.include?(x) || x.to_s.empty?
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

    def nff
      compute_nff if @recompute_nff
      @nff
    end

    def first(*args)
      compute_nff if @recompute_nff

      stack = args.flatten

      set = Set[]
      stack.each do |x|
        set.add x unless symbol?(x)
        set.merge @nff[:first, x] if symbol?(x)
        break unless symbol?(x) && @nff[:nullable, x]
      end

      set
    end

    private

    def compute_nff
      @nff = Table.new(index_label: :symbol)
      symbols.each { |x| @nff.add_row(x, nullable: false, first: Set[], follow: Set[]) }

      # 1. first[z] <- {z} for each terminal z
      @terminals.each { |z| @nff[:first, z].add z }

      loop do
        modified = false

        # 2. For each production X -> Y1Y2...Yk
        @productions.each do |p|
          if p.null? && !@nff[:nullable, p.name]
            @nff[:nullable, p.name] = true
            modified = true
          end

          # 3. For each i from 1 to k
          p.length.times do |i|
            nullable = p.rhs.map { |y| @nff[:nullable, y] }

            # 4. If all Yi are nullable, then nullable[X] <- true
            if nullable.count(true) == p.length && !@nff[:nullable, p.name]
              @nff[:nullable, p.name] = true
              modified = true
            end

            # 5. If Y1...Yi-1 are nullable, then first[X] <- first[X] U first[Yi]
            if i == 0 || nullable[..i-1].count(true) == i - 1
              old = @nff[:first, p.name].clone
              @nff[:first, p.name].merge @nff[:first, p[i]]
              modified = true unless @nff[:first, p.name] == old
            end

            # 6. For each j from i + 1 to k
            (i + 1..p.length - 1).each do |j|
              # 7. If Yi+1...Yj-1 are nullable, then follow[Yi] <- follow[Yi] U first[Yj]
              if j - i - 1 == 0 || nullable[i+1..j-1].count(true) == j - i - 1
                old = @nff[:follow, p[i]]
                @nff[:follow, p[i]] = @nff[:follow, p[i]].merge @nff[:first, p[j]]
                modified = true unless @nff[:follow, p[i]] == old
              end
            end
          end
        end

        break unless modified
      end

      @recompute_nff = false
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
      @unique_name_count ||= {}
      @unique_name_count[basename] ||= 0
      name = "#{basename}#{@unique_name_count[basename]}".to_sym
      @unique_name_count[basename] += 1
      while symbols.include?(name)
        name = "#{basename}#{@unique_name_count[basename]}".to_sym
        @unique_name_count[basename] += 1
      end
      name
    end
  end
end
