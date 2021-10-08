# frozen_string_literal: true

require 'benchmark'
require_relative 'production'
require_relative 'item'
require_relative 'table'
require_relative 'action'
require_relative 'item_set'
require_relative 'parse_tree'

module Lalrrb
  class Parser
    attr_reader :grammar, :table, :lexer, :states

    def initialize(grammar, **opts)
      opts[:benchmark_times] = BenchmarkTimes.new unless opts[:benchmark_times].is_a?(BenchmarkTimes)
      opts[:benchmark] = false if opts[:benchmark].nil?
      opts[:benchmark_caption] ||= Benchmark::CAPTION
      opts[:benchmark_label_width] ||= 10
      opts[:benchmark_format] ||= Benchmark::FORMAT
      opts[:benchmark_show_total] = true if opts[:benchmark_show_total].nil?

      if opts[:benchmark]
        benchmark_args = [opts[:benchmark_caption], opts[:benchmark_label_width], opts[:benchmark_format]]
        benchmark_args << "total" if opts[:benchmark_show_total]
        Benchmark.benchmark(*benchmark_args) do |bm|
          opts[:benchmark_times]["convert"] = bm.report("convert") { convert_grammar(grammar) }
          opts[:benchmark_times]["nff table"] = bm.report("nff table") { @grammar.nff }
          opts[:benchmark_times]["states"] = bm.report("states") { construct_states }
          opts[:benchmark_times]["table"] = bm.report("table") { construct_table }

          [opts[:benchmark_times].total] if opts[:benchmark_show_total]
        end
      else
        convert_grammar(grammar)
        construct_states
        construct_table
      end
    end

    def parse(text, debug: false)
      input = @lexer.tokenize(text, debug: debug)

      debug_longest_input = [input.map { |t| t.name.to_s.length }.max, 9].max
      if debug
        puts ''
        puts "step state #{"lookahead".ljust(debug_longest_input)} #{"symbols".ljust(35)} #{"stack".ljust(20)} action"
        puts "==== ===== #{'=' * debug_longest_input} #{'=' * 35} #{'=' * 20} #{'=' * 15}"
      end
      stack = [{ symbol: nil, state: 0, node: nil }]
      step = 0
      loop do
        step += 1
        raise Error, "reached end of input without accepting" if input.empty?

        state = stack.last[:state]
        action = @table[input.first.name, state]

        if debug
          print step.to_s.ljust(4)
          print " "
          print state.to_s.ljust(5)
          print " "
          print input.first.name.to_s.ljust(debug_longest_input)
          print " "
          symbols = ""
          stack.reverse.each_with_index do |s, index|
            next if s[:symbol].nil?

            next_s = "#{s[:symbol].name}#{symbols.empty? ? '' : " #{symbols}"}"
            if next_s.length > 34 || (next_s.length == 34 && index < stack.length - 1)
              symbols = "..#{symbols}"
              break
            end
            symbols = next_s
          end
          print symbols.ljust(35)
          print " "
          states = ""
          stack.reverse.each_with_index do |s, index|
            next_s = "#{s[:state]}#{states.empty? ? '' : ",#{states}"}"
            if next_s.length > 16 || (next_s.length == 16 && index < stack.length - 1)
              states = "..,#{states}"
              break
            end
            states = next_s
          end
          print "[#{states}]".ljust(20)
          print " "
          case action&.type
          when :accept then puts "accept"
          when :shift then puts "shift to state #{action.arg}"
          when :reduce then puts "reduce by: #{@grammar[action.arg]}"
          when nil then puts "error: no action available"
          else puts action.type.to_s
          end
        end

        case action&.type
        when :shift
          token = input.shift
          stack << { symbol: token, state: action.arg, node: ParseTree.new(token) }
        when :reduce
          p = @grammar[action.arg].clone
          popped = stack.pop(p.length)
          goto = @table[p.name, stack.last[:state]].arg
          stack << { symbol: p.name, state: goto, node: ParseTree.new(p, popped.map { |x| x[:node] }) }
        when :accept then break
        when nil
          matches = @grammar.terminals.filter { |z| !@table[z, state].nil? }.flatten
          matches = matches.map { |m| m.is_a?(Regexp) ? "/#{m.source}/" : "`#{m}'" }
          matches = matches.length <= 1 ? matches.first : "#{matches[..-2].join(', ')} or #{matches[-1]}"
          ahead = input.first.name.is_a?(Regexp) ? "/#{input.first.name.source}/" : "`#{input.first.name}'"
          raise Error, "#{input.first.position}: Expected #{matches} but encountered #{ahead}."
        else break
        end
      end

      stack.last[:node].root.simplify
    end

    def graphviz
      g = GraphViz.new(:G, type: :digraph, rankdir: :LR)

      start_node = g.add_nodes("start", label: '', width: 0.01, shape: :plaintext)
      accept_node = g.add_nodes("accept", label: 'Accept', shape: :doublecircle)

      nodes = []
      @states.each_with_index do |s,i|
        ps = []
        ts = []
        s.each do |item|
          p = item.production.to_s(position: item.position)
          t = item.lookahead == :EOF ? '$' : item.lookahead.to_s
          t = '","' if t == ','
          if index = ps.find_index(p)
            ts[index] += ",#{t}"
          else
            ps << p
            ts << t
          end
        end

        label = "State #{i}:"
        (0..ps.length - 1).each do |i|
          label += "\n(#{ps[i]}, #{ts[i]})"
        end
        nodes << g.add_nodes("state#{i}", label: label, shape: :box, style: :rounded)
      end

      g.add_edges(start_node, nodes.first)
      @states.each_with_index do |s,i|
        @grammar.symbols.each do |z|
          action = @table[z, i]
          z = "$" if z == :EOF
          case action&.type
          when :shift, :goto then g.add_edges(nodes[i], nodes[action.arg], label: z.to_s)
          when :accept then g.add_edges(nodes[i], accept_node, label: z.to_s)
          end
        end
      end

      g
    end

    def pretty_print
      @states.each_with_index do |s, i|
        puts "" if i > 0
        puts "State #{i}:"
        puts '=' * (7 + @states.length.to_s.length)
        print "items = "
        s.pretty_print
        edges = {}
        @grammar.symbols.each do |z|
          action = @table[z, i]
          case action&.type
          when :shift then edges[z] = "shift to state #{action.arg}"
          when :reduce then edges[z] = "reduce by: #{@grammar[action.arg]}"
          when :accept then edges[z] = "accept"
          end
        end
        key_length = edges.keys.map(&:to_s).map(&:length).max
        if edges.empty?
          puts "actions = {}"
        else
          puts "actions = {"
          edges.each_with_index { |(z,a), j| puts "  #{((z == :EOF ? '$' : z.to_s)+':').ljust(key_length + 1)} #{a}#{j < edges.length - 1 ? ',' : ''}" }
          puts "}"
        end
      end
    end

    private

    def convert_grammar(grammar)
      @grammar = grammar.is_a?(BasicGrammar) ? grammar.clone : grammar.to_basic
      @grammar.transform_del
      @grammar.merge_duplicate_rules(generated_only: true)

      start_name = "#{@grammar.start}'"
      start_name = "#{start_name}'" while @grammar.symbols.include? start_name
      @grammar.add_production(start_name, @grammar.start, :EOF, generated: true)
      @grammar.start = start_name

      @lexer = @grammar.lexer
      @grammar.terminals.each do |z|
        next if @lexer.tokens.include?(z) || z == :EOF

        @lexer.token(z, z)
      end
    end

    def lookup_state(item_set)
      return nil if item_set&.empty?

      core = item_set.core

      @states.each_with_index do |state, index|
        return index if state.core == core
      end

      nil
    end

    def construct_states
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
    end

    # Construct the parsing table
    def construct_table
      @table = Table.new(index_label: :State)
      @grammar.terminals.each { |x| @table.add_column(x) }
      @grammar.nonterminals.each { |x| @table.add_column(x) unless x == @grammar.start }
      @table.group_add(:Action, *@grammar.terminals.to_a)
      @table.group_add(:Goto, *@grammar.nonterminals.to_a)

      @states.each_with_index do |state, index|
        @table.add_row
        # a. GOTO[A, i] = goto j if goto(state, A) = state j
        @grammar.nonterminals.each do |a|
          j = lookup_state(state.goto(a))
          @table[a, index] = Action.goto(j) unless j.nil?
        end

        state.items.each do |item|
          # b. If item = (S' -> S ., $), then ACTION[$, index] = accept
          if item.production.name == @grammar.start && item.at_end? && item.lookahead == :EOF
            @table[:EOF, index] = Action.accept
          # c. If item = (A -> alpha . a beta, b) with a a terminal, then ACTION[a, index] = shift j where goto(state, a) = state j
          elsif @grammar.terminal? item.next
            j = lookup_state(state.goto(item.next))
            @table[item.next, index] = Action.shift(j) unless j.nil?
          # d. If item = (A -> alpha ., a), A != S', then ACTION[a, index] = reduce A -> alpha
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
