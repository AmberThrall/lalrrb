# frozen_string_literal: true

require_relative 'production'
require_relative 'item'
require_relative 'table'
require_relative 'action'
require_relative 'state'

module Lalrrb
  class Parser
    attr_reader :productions, :states, :table, :nff_table

    def initialize(grammar)
      @grammar = grammar
      @productions = []
      @productions << Production.new(unique_name(@grammar.start, :start), @grammar.start, :EOF)
      @grammar.rules.each { |name, rule| convert_rule(rule) }
      @terminals = @grammar.tokens.clone
      @terminals << :EOF
      compute_nff_table
      construct_table
    end

    def graphviz
      g = GraphViz.new(:G, type: :digraph, rankdir: :LR)

      @states.each_with_index { |state, index| g.add_nodes(index.to_s, label: state.to_s(border: false).gsub("\n", "\\n"), shape: :rectangle) }

      @edges.each { |edge| g.add_edges(edge[:from].to_s, edge[:to].to_s, label: edge[:condition]) }

      g
    end

    private

    def compute_nff_table
      @nff_table = Table.new([:nullable, :first, :follow])

      # 0. first[x] = [], nullable[x] = false, follow[x] = [] for all x
      @productions.map(&:name).uniq.each { |x| @nff_table.add_row([false, [], []], label: x) }
      @terminals.each { |z| @nff_table.add_row([false, [], []], label: z) }

      # 1. first[z] <- [z] for all terminals z
      @terminals.each { |z| @nff_table[:first, z] = [z] }

      loop do
        @nff_table.clear_modified

        @productions.each do |p| # X -> Y1Y2...Yk
          nullable_list = p.rhs.map { |x| @nff_table[:nullable, x] }

          # 2. if Y1, Y2, ..., Yk nullable, then nullable[X] = true
          if nullable_list.count(true) == p.length
            @nff_table[:nullable, p.name] = true
          end

          (0..p.length - 1).each do |i|
            # 3. if Y1, ... Yi-1 nullable, then first[X] = first[X] U first[yi]
            if i == 0 || nullable_list[0..i - 1].count(true) == nullable_list[0..i - 1].length
              @nff_table[:first, p.name] = [@nff_table[:first, p.name], @nff_table[:first, p[i]]].flatten.uniq
            end

            # 4. if Yi+1 ... Yk nullable, then follow[Yi] = follow[Yi] U follow[X]
            if nullable_list[i + 1..].count(true) == nullable_list[i + 1..].length
              @nff_table[:follow, p[i]] = [@nff_table[:follow, p[i]], @nff_table[:follow, p.name]].flatten.uniq
            end

            (i + 1..p.length - 1).each do |j|
              # 5. if Yi+1 ... Yj-1 nullable, then follow[Yi] = follow[Yi] U first[Yj]
              if nullable_list[i + 1..j - 1].count(true) == nullable_list[i + 1..j - 1].length
                @nff_table[:follow, p[i]] = [@nff_table[:follow, p[i]], @nff_table[:first, p[j]]].flatten.uniq
              end
            end
          end
        end

        break unless @nff_table.modified?
      end
    end

    def construct_table
      @states ||= []
      @states << closure(Item.new(@productions.first, 0, nil))
      @edges = []
      @table = Table.new(@terminals)
      @productions.map(&:name).uniq[1..].each { |p| @table.add_column([], heading: p) }
      @table.add_row([])

      loop do
        @table.clear_modified

        @states.each_with_index do |state, index|
          state.items.each do |item|
            next if item.next.nil?
            if item.next == :EOF
              @table[:EOF, index] = Action.accept
              next
            end
            j = goto(state, item.next)

            # LALR(1) merges mostly identical states
            add_state = true
            @states.each do |s|
              if s == j
                add_state = false
                break
              elsif s.mostly_equal?(j)
                s.merge(j)
                add_state = false
                break
              end
            end

            if add_state
              @states << j
              @table.add_row([])
            end

            edge = { from: index, to: @states.find_index(j), condition: item.next }
            unless edge[:to].nil? || @edges.include?(edge)
              @edges << edge
              @table[item.next, index] = Action.goto(edge[:to]) if productions.map(&:name).include? item.next
              @table[item.next, index] = Action.shift(edge[:to]) if @grammar.tokens.include? item.next
            end
          end
        end

        break if @table.modified?
      end

      @states.each_with_index do |state, index|
        state.items.each do |item|
          if item.next.nil?
            find = @productions.find_index(item.production)
            @table[item.lookahead, index] = Action.reduce(find)
          end
        end
      end
    end

    def first(*args)
      stack = Array(args).flatten
      stack.delete_if { |s| s.to_s.empty? }

      list = []
      stack.each do |s|
        list.concat @nff_table[:first, s]
        break unless @nff_table[:nullable, s]
      end

      list
    end

    def closure(items)
      state = items.is_a?(State) ? items.clone : State.new(items)

      loop do
        length = state.length
        state.items.each do |i|
          @productions.filter { |p| p.name == i.next }.each do |p|
            first(i.production.rhs[i.position + 1..], i.lookahead).each do |w|
              item = Item.new(p, 0, w)
              state << item unless state.include?(item)
            end
          end
        end

        break if state.length == length
      end

      state
    end

    def goto(items, symbol)
      items = items.items if items.is_a?(State)
      j = State.new
      items.filter { |i| i.next == symbol }.each do |i|
        j << Item.new(i.production, i.position + 1, i.lookahead) if i.position < i.production.length
      end
      closure(j)
    end

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
