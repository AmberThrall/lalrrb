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

      @grammar.add_production(start_name, @grammar.start, :EOF)
      @grammar.start = start_name

      @grammar.terminals.each { |z| @lexer.token(z, z) if z.is_a?(String) }

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
                     when nil
                       reductions = @grammar.terminals.filter { |z| @table[z, state]&.type == :reduce }
                       action = @table[reductions.first,state] unless reductions.empty?
                       action&.type.nil? ? "no action available" : "reduce by #{@grammar[action.arg]}"
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
        when nil
          matches = @grammar.terminals.filter { |z| !@table[z, state].nil? }
          raise StandardError, "Expected #{matches.join(', ')} but encountered #{input.first.name} in state #{state}"
        else
          return [stack.last[:node], step_table]
        end
      end

      [stack.last[:node], step_table]
    end

    private

    def lookup_state(item_set)
      return nil if item_set&.empty?

      core = item_set.core

      @states.each_with_index do |state, index|
        return index if state.core == core
      end

      nil
    end

    def construct_table
      @states = [ItemSet.new(@grammar, Item.new(@grammar[@grammar.start], 0, :EOF)).closure]

      # 1. Construct the states for LR(1)
      loop do
        modified = false

        @states.each_with_index do |state, index|
          @grammar.symbols.each do |x|
            j = state.goto(x)
            next if j.empty? || @states.include?(j)

            @states << j
            modified = true
          end
        end

        break unless modified
      end

      # 2. Merge states with identical cores.
      @states.each_with_index do |s,i|
        next if s.empty?

        core = s.core

        @states[i + 1..].each do |t|
          next unless core == t.core

          s.merge t
          t.clear
        end
      end
      @states.delete_if { |s| s.empty? }

      # 3. Construct the parsing table
      @table = Table.new(index_label: :state)
      @grammar.terminals.each { |x| @table.add_column([], heading: x) }
      @grammar.nonterminals.each { |x| @table.add_column([], heading: x) unless x == @grammar.start }
      @table.add_group(:action, @grammar.terminals.to_a)
      @table.add_group(:goto, @grammar.nonterminals.to_a)

      @states.each_with_index do |state, index|
        @table.add_row([])
        # 3a. GOTO[A, i] = goto j if goto(state, A) = state j
        @grammar.nonterminals.each do |a|
          j = lookup_state(state.goto(a))
          @table[a, index] = Action.goto(j) unless j.nil?
        end

        state.items.each do |item|
          # 3b. If item = (S' -> S ., $), then ACTION[$, index] = accept
          if item.production.name == @grammar.start && item.at_end? && item.lookahead == :EOF
            @table[:EOF, index] = Action.accept
          # 3c. If item = (A -> alpha . a beta, b) with a a terminal, then ACTION[a, index] = shift j where goto(state, a) = state j
          elsif @grammar.terminal? item.next
            j = lookup_state(state.goto(item.next))
            @table[item.next, index] = Action.shift(j) unless j.nil?
          # 3d. If item = (A -> alpha ., a), A != S', then ACTION[a, index] = reduce A -> alpha
          elsif item.at_end? && item.production.name != @grammar.start
            r = @grammar.productions.find_index(item.production)
            @table[item.lookahead, index] = Action.reduce(r) unless r.nil?
          end
        end
      end
    end
  end
end
