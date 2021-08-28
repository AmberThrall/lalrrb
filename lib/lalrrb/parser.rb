# frozen_string_literal: true

require_relative 'production'
require_relative 'item'
require_relative 'table'
require_relative 'action'
require_relative 'item_set'
require_relative 'parse_tree'

module Lalrrb
  class Parser
    attr_reader :grammar, :states, :table, :lexer

    def initialize(grammar)
      @grammar = grammar.is_a?(BasicGrammar) ? grammar.clone : grammar.to_basic
      @grammar.merge_duplicate_rules

      start_name = "#{@grammar.start}'"
      start_name = "#{start_name}'" while @grammar.symbols.include? start_name
      @grammar.add_production(start_name, @grammar.start, :EOF, generated: true)
      @grammar.start = start_name

      @lexer = @grammar.lexer
      @grammar.terminals.each { |z| @lexer.token(z, z) }

      construct_table
    end

    def parse(text, raise_on_error: true, return_steps: false)
      step_table = Table.new(index_label: :Step)
      [:States, :Tokens, :Ahead, :Action].each { |s| step_table.add_column(s) }
      step_table.group_add(:Stack, :States, :Tokens)

      stack = [{ symbol: nil, state: 0, node: nil }]
      @lexer.start(text)
      ahead = nil
      loop do
        state = stack.last[:state]
        action = nil
        if ahead.nil?
          @lexer.next.each do |t|
            action = @table[t.name, state]
            next if action.nil?

            @lexer.accept(t)
            ahead = t
            break
          end
        else
          action = @table[ahead.name, state]
        end

        action_msg = case action&.type
                     when :shift then "shift to state #{action.arg}"
                     when :reduce then "reduce by #{@grammar[action.arg]}"
                     when nil then "no action available"
                     else action.type.to_s
                     end
        if return_steps
          step_table.add_row((step_table.nrows + 1).to_s, **{
            States: stack.map { |s| s[:state]}.join(' '),
            Tokens: stack.filter { |s| !s.nil? }.map { |s| s[:symbol]}.join(' '),
            Ahead: ahead,
            Action: action_msg
          })
        end

        case action&.type
        when :shift
          stack << { symbol: ahead, state: action.arg, node: ParseTree.new(ahead) }
          ahead = nil
        when :reduce
          p = @grammar[action.arg]
          popped = stack.pop(p.length)
          goto = @table[p.name, stack.last[:state]].arg
          stack << { symbol: p.name, state: goto, node: ParseTree.new(p, popped.map { |x| x[:node] }) }
        when :accept then break
        when nil
          matches = @grammar.terminals.filter { |z| !@table[z, state].nil? }
          err = "Expected #{matches.join(', ')} but encountered '#{ahead}' in state #{state}"
          raise StandardError, err if raise_on_error
          warn "Error: #{err}"

          break
        else break
        end
      end

      return [stack.last[:node].root.simplify, step_table] if return_steps
      stack.last[:node].root.simplify
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
      @table = Table.new(index_label: :State)
      @grammar.terminals.each { |x| @table.add_column(x) }
      @grammar.nonterminals.each { |x| @table.add_column(x) unless x == @grammar.start }
      @table.group_add(:Action, *@grammar.terminals.to_a)
      @table.group_add(:Goto, *@grammar.nonterminals.to_a)

      @states.each_with_index do |state, index|
        @table.add_row
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
            next if r.nil?

            @table[item.lookahead, index] = Action.reduce(r)
            @grammar.terminals.each { |z| @table[z, index] = Action.reduce(r) if @table[z, index].nil? }
          end
        end
      end
    end
  end
end
