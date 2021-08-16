# frozen_string_literal: true

require_relative 'production'
require_relative 'item'
require_relative 'table'
require_relative 'action'
require_relative 'item_set'
require_relative 'parse_tree'

module Lalrrb
  class Parser
    attr_reader :grammar, :states, :table, :nff_table

    def initialize(grammar)
      @grammar = grammar.is_a?(BasicGrammar) ? grammar : grammar.to_basic
      @lexer = grammar.is_a?(BasicGrammar) ? Lexer.new : grammar.lexer

      start_name = "#{@grammar.start}'"
      start_name = "#{start_name}'" while @grammar.symbols.include? start_name

      @grammar.add_production(start_name, @grammar.start)
      @grammar.start = start_name

      @grammar.terminals.each { |z| @lexer.token(z, z) if z.is_a?(String) }

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
      input = @lexer.tokenize(text)
      step_table = Table.new(['States', 'Tokens', 'Input', 'Action'], index_label: 'Step')
      step_table.add_group('Stack', 'States', 'Tokens')

      stack = [{ symbol: :EOF, state: 0, node: nil }]
      loop do
        state = stack.last[:state]
        action = @table[input.first.name, state]

        action_msg = case action&.type
                     when :shift then "shift to state #{action.arg}"
                     when :reduce then "reduce by #{@grammar[action.arg]}"
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
          symbol = input.shift
          stack << { symbol: symbol, state: action.arg, node: ParseTree.new(symbol) }
        when :reduce
          p = @grammar[action.arg]
          popped = stack.pop(p.length)
          goto = @table[p.name, stack.last[:state]].arg
          stack << { symbol: p.name, state: goto, node: ParseTree.new(p, popped.map { |x| x[:node] }) }
        when :accept
          return [stack.last[:node], step_table]
        else
          return [stack.last[:node], step_table]
        end
      end

      [stack.last[:node], step_table]
    end

    private

    def compute_nff_table
      @nff_table = Table.new([:nullable, :first, :follow], index_label: "X")

      # 0. first[x] = [], nullable[x] = false, follow[x] = [] for all x
      @grammar.symbols.each { |z| @nff_table.add_row([false, Set[], Set[]], label: z) }

      # 1. first[z] = [z] for all terminals z
      @grammar.terminals.each { |z| @nff_table[:first, z] = Set[z] }
      @nff_table.add_row([false, Set[:EOF], Set[]], label: :EOF)

      loop do
        old_table = @nff_table.clone

        @grammar.productions.each do |p| # X -> Y1Y2...Yk
          nullable_list = p.rhs.map { |x| @nff_table[:nullable, x] }

          # 2. if Y1, Y2, ..., Yk nullable, then nullable[X] = true
          if nullable_list.count(true) == nullable_list.length
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

        break unless @nff_table == old_table
      end
    end

    def construct_table
      @states = [closure(Item.new(@grammar[@grammar.start], 0, :EOF))]

      # 1. Construct the states for LR(1)
      loop do
        modified = false

        @states.each do |state|
          @grammar.symbols.each do |x|
            j = goto(state, x)
            next if j.empty? || @states.include?(j)

            @states << j
            modified = true
          end
        end

        break unless modified
      end

      # 2. Merge states with identical cores.

      # 3. Construct the parsing table
      @table = Table.new(index_label: :state)
      @grammar.terminals.each { |x| @table.add_column([], heading: x) }
      @table.add_column([], heading: :EOF)
      @grammar.nonterminals.each { |x| @table.add_column([], heading: x) unless x == @grammar.start }
      @table.add_group(:action, @grammar.terminals.to_a, :EOF)
      @table.add_group(:goto, @table.ungrouped)

      @states.each_with_index do |state, index|
        @table.add_row([])
        # 3a. ACTION[A, i] = goto j if goto(state, A) = state j
        @grammar.nonterminals.each do |a|
          j = @states.find_index(goto(state, a))
          @table[a, index] = Action.goto(j) unless j.nil?
        end

        state.items.each do |item|
          # 3b. If item = (S' -> S ., $), then ACTION[$, index] = accept
          if item.production.name == @grammar.start && item.at_end? && item.lookahead == :EOF
            @table[:EOF, index] = Action.accept
          # 3c. If item = (A -> alpha . a beta, b) with a a terminal, then ACTION[a, index] = shift j where goto(state, a) = state j
          elsif @grammar.terminal? item.next
            j = @states.find_index(goto(state, item.next))
            @table[item.next, index] = Action.shift(j) unless j.nil?
          # 3d. If item = (A -> alpha ., a), A != S', then ACTION[a, index] = reduce A -> alpha
          elsif item.at_end? && item.production.name != @grammar.start
            r = @grammar.productions.find_index(item.production)
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

    def closure(set)
      set = set.is_a?(ItemSet) ? set.clone : ItemSet.new(*Array(set))

      loop do
        old_size = set.size

        set.items.each do |item|
          Array(@grammar[item.next]).each do |p|
            first(item.production.rhs[item.position + 1..], item.lookahead).each do |b|
              set.add Item.new(p, 0, b)
            end
          end
        end

        break if set.size == old_size
      end

      set
    end

    def goto(set, symbol)
      set = set.is_a?(ItemSet) ? set.clone : ItemSet.new(*Array(set))

      j = ItemSet.new
      set.items.filter { |i| i.next == symbol }.each do |i|
        j.add i.shift unless i.at_end?
      end
      closure(j)
    end
  end
end
