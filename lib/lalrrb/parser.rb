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
      @productions << Production.new(unique_name(@grammar.start, :start), @grammar.start, start_production: true)
      @grammar.rules.each { |name, rule| convert_rule(rule) }
      @nonterminals = @productions.map(&:name).uniq
      @terminals = @grammar.tokens.clone << :EOF
      @symbols = [@nonterminals, @terminals].flatten
      compute_nff_table
      construct_table
    end

    def graphviz
      g = GraphViz.new(:G, type: :digraph, rankdir: :LR)

      @states.each_with_index { |state, index| g.add_nodes(index.to_s, label: state.to_s(border: false).gsub("\n", "\\n"), shape: :rectangle) }

      @edges.each { |edge| g.add_edges(edge[:from].to_s, edge[:to].to_s, label: edge[:condition]) }

      g
    end

    def parse(text)
      input = @grammar.lexer.tokenize(text)
      step_table = Table.new(['States', 'Tokens', 'Input', 'Action'], index_label: 'Step')
      step_table.add_group('Stack', 'States', 'Tokens')

      stack = [{ symbol: :EOF, state: 0 }]
      loop do
        state = stack.last[:state]
        action = @table[input.first.name, state]

        action_msg = case action&.type
                     when :shift then "shift to state #{action.arg}"
                     when :reduce then "reduce by #{@productions[action.arg]}"
                     when nil then "no action available"
                     else action.type.to_s
                     end
        step_table.add_row([
          stack.map { |s| s[:state]}.join(' '),
          stack.map { |s| s[:symbol]}.join(' '),
          input.join(' '),
          action_msg
        ], label: (step_table.nrows + 1).to_s)

        case action&.type
        when :shift
          stack << { symbol: input.shift, state: action.arg }
        when :reduce
          p = @productions[action.arg]
          stack.pop(p.length)
          goto = @table[p.name, stack.last[:state]].arg
          stack << { symbol: p.name, state: goto }
        when :accept
          return step_table
        else
          return step_table
        end
      end

      step_table
    end

    private

    def compute_nff_table
      @nff_table = Table.new([:nullable, :first, :follow], index_label: "X")

      # 0. first[x] = [], nullable[x] = false, follow[x] = [] for all x
      @symbols.each { |z| @nff_table.add_row([false, Set[], Set[]], label: z) }

      # 1. first[z] = [z] for all terminals z
      @terminals.each { |z| @nff_table[:first, z] = Set[z] }

      loop do
        old_table = @nff_table.clone

        @productions.each do |p| # X -> Y1Y2...Yk
          nullable_list = p.rhs.map { |x| @nff_table[:nullable, x] }

          # 2. if Y1, Y2, ..., Yk nullable, then nullable[X] = true
          if nullable_list.count(true) == p.length
            @nff_table[:nullable, p.name] = true
          end

          (0..p.length - 1).each do |i|
            # 3. if Y1, ... Yi-1 nullable, then first[X] = first[X] U first[yi]
            if i == 0 || nullable_list[0..i - 1].count(true) == nullable_list[0..i - 1].length
              @nff_table[:first, p.name] = @nff_table[:first, p.name].merge @nff_table[:first, p[i]]
            end

            # 4. if Yi+1 ... Yk nullable, then follow[Yi] = follow[Yi] U follow[X]
            if nullable_list[i + 1..].count(true) == nullable_list[i + 1..].length
              @nff_table[:follow, p[i]] = @nff_table[:follow, p[i]].merge @nff_table[:follow, p.name]
            end

            (i + 1..p.length - 1).each do |j|
              # 5. if Yi+1 ... Yj-1 nullable, then follow[Yi] = follow[Yi] U first[Yj]
              if nullable_list[i + 1..j - 1].count(true) == nullable_list[i + 1..j - 1].length
                @nff_table[:follow, p[i]] = @nff_table[:follow, p[i]].merge @nff_table[:first, p[j]]
              end
            end
          end
        end

        break #unless @nff_table == old_table
      end
    end

    def construct_table
      @states = []
      @states << closure(Item.new(@productions.first, 0, :EOF))
      @edges = []

      # 1. Construct the states for LR(1)
      loop do
        modified = false

        @states.each do |state|
          @symbols.each do |x|
            new_state = goto(state, x)
            next if new_state.empty? || @states.include?(new_state)

            @states << new_state
            modified = true
          end
        end

        break unless modified
      end

      # 2. Construct the parsing table
      @table = Table.new(@terminals.clone, index_label: :state)
      @nonterminals[1..].each { |x| @table.add_column([], heading: x) }
      @table.add_group(:action, @terminals)
      @table.add_group(:goto, @table.ungrouped)\

      @states.each_with_index do |state, index|
        @table.add_row([])
        # 2a. ACTION[A, i] = goto j if goto(state, A) = state j
        @nonterminals.each do |a|
          j = @states.find_index(goto(state, a))
          @table[a, index] = Action.goto(j) unless j.nil?
        end

        state.items.each do |item|
          # 2b. If item = (S' -> S ., $), then ACTION[$, index] = accept
          if item.production.start_production? && item.at_end? && item.lookahead == :EOF
            @table[:EOF, index] = Action.accept
          # 2c. If item = (A -> alpha . a beta, b) with a a terminal, then ACTION[a, index] = shift j where goto(state, a) = state j
          elsif @terminals.include? item.next
            j = @states.find_index(goto(state, item.next))
            @table[item.next, index] = Action.shift(j) unless j.nil?
          # 2d. If item = (A -> alpha ., a), A != S', then ACTION[a, index] = reduce A -> alpha
          elsif item.at_end? && item.production.name != @productions.first.name
            r = @productions.find_index(item.production)
            @table[item.lookahead, index] = Action.reduce(r) unless r.nil?
          end
        end
      end
    end

    def first(*args)
      stack = Array(args).flatten
      stack.delete_if { |s| s.to_s.empty? }

      set = Set[]
      stack.each do |s|
        set.merge @nff_table[:first, s]
        break unless @nff_table[:nullable, s]
      end

      set
    end

    def closure(items)
      state = items.is_a?(State) ? items.clone : State.new(items)

      loop do
        old_size = state.size

        state.items.each do |item|
          @productions.filter { |p| p.name == item.next }.each do |p|
            first(item.production.rhs[item.position + 1..], item.lookahead).each do |b|
              state.add Item.new(p, 0, b)
            end
          end
        end

        break if state.size == old_size
      end

      state
    end

    def goto(items, symbol)
      items = items.items if items.is_a?(State)

      j = State.new
      items.filter { |i| i.next == symbol }.each do |i|
        j.add i.shift
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
          @productions << Production.new(name_inf)
          [[name] * nonterminal.min, name_inf].flatten
        else
          name_repeat = "#{basename}_repeat".to_sym
          (0..nonterminal.max - nonterminal.min).each do |i|
            @productions << Production.new(name_repeat, [[name] * i].flatten)
          end
          [[name] * nonterminal.min, name_repeat].flatten
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
