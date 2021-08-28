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
      return add_production(arg0.name, *arg0.rhs, generated: arg0.generated?) if arg0.is_a?(Production)

      name = arg0
      ps = convert(*args).map do |rhs|
        rhs = rhs[:rhs]
        p = Production.new(name, rhs, generated: generated)
        next if @productions.include?(p)

        @productions << p
        @nonterminals.add name unless nonterminal?(name)
        @terminals.delete name
        @lexer.delete_token name
        rhs.each do |x|
          @terminals.add x unless @nonterminals.include?(x)
          @lexer.token(x, x) if !@nonterminals.include?(x)
        end
        p
      end

      ps.length > 1 ? ps : ps.first
    end

    def delete_production(index)
      p = self[index]
      return nil if p.nil?

      @productions.delete(p)
      @nonterminals.delete p.name if @productions.filter { |p2| p2.name == p.name }.empty?

      p.rhs.filter { |z| @terminals.include?(z) }.each do |z|
        delete_terminal = true
        @productions.each do |p2|
          p2.rhs.each { |z2| delete_terminal = false if z == z2 }
          break unless delete_terminal
        end

        if delete_terminal
          @terminals.delete(z)
          @lexer.delete_token(z)
        end
      end

      @recompute_nff = true
      p
    end

    def delete_rule(rulename)
      @productions.filter { |p| p.name == rulename }.each { |p| delete_production(p) }
    end

    def replace_all(search, replace)
      @productions.each do |p|
        p.length.times do |i|
          if search == p[i]
            @recompute_nff = true
            p[i] = replace
          end
        end
      end
    end

    def merge_duplicate_rules
      # Get the set of duplicates
      duplicates = {}
      @nonterminals.each do |x|
        skip = false
        duplicates.each { |k,v| skip = true if v.include?(x) }
        break if skip

        productions_x = @productions.filter { |p| p.name == x }
        duplicates[x] = []

        @nonterminals.filter { |y| y != x }.each do |y|
          productions_y = @productions.filter { |p| p.name == y }
          next if productions_x.length != productions_y.length

          duplicates[x] << y
          productions_x.each do |px|
            matched_production = nil
            productions_y.each do |py|
              next if px.length != py.length

              is_match = true
              px.length.times do |i|
                unless px[i] == py[i] || (px[i] == x && py[i] == y)
                  is_match = false
                  break
                end
              end

              if is_match
                matched_production = py
                break
              end
            end

            if matched_production.nil?
              duplicates[x].delete(y)
              break
            end
          end
        end
      end

      # Remove duplicates keeping the first one.
      duplicates.each do |x,v|
        v.each do |y|
          replace_all(y, x) # Replace all instances of y with x
          delete_rule(y)
        end
      end
    end

    # START: Eliminate the start symbol from right hand sides.
    def transform_start
      @productions.each do |p|
        next unless p.rhs.include?(@start)

        new_start = unique_name(:S)
        add_production(new_start, @start, generated: true)
        @start = new_start
        break
      end
    end

    # TERM: Eliminate rules with nonsolitary terminals
    def transform_term
      terms = {}
      @productions.each do |p|
        next unless p.length == 1 && terminal?(p[0]) && Array(self[p.name]).length == 1

        terms[p[0]] = p.name
      end

      @productions.each do |p|
        next unless p.length > 1

        new_rhs = []
        p.rhs.each do |z|
          if terms.include?(z)
            new_rhs << terms[z]
          elsif nonterminal?(z)
            new_rhs << z
          else
            name = "N\"#{z}\""
            name = "N#{z}".to_sym if z.is_a?(Symbol) || !z.to_s.match(/[A-Za-z0-9_]+/).nil?
            name = unique_name(:N) if symbol?(name)
            add_production(name, z, generated: true)
            new_rhs << name
            terms[z] = name
          end
        end

        @recompute_nff unless p.rhs == new_rhs
        p.rhs = new_rhs
      end
    end

    # BIN: Eliminate right-hand sides with more than 2 nonterminals
    def transform_bin
      @productions.each do |p|
        next unless p.length > 2

        next_sym = nil
        count = p.rhs.length - 2
        p.rhs[1..].reverse.each do |x|
          if next_sym.nil?
            next_sym = x
          else
            name = "#{x}_#{next_sym}"
            name = name.to_sym if x.is_a?(Symbol) && next_sym.is_a?(Symbol)
            name = unique_name("#{name}_".to_sym) if symbol?(name)
            add_production(name, x, next_sym, generated: true)
            next_sym = name
            count -= 1
          end
        end

        p.rhs[1] = next_sym
        p.rhs = p.rhs[0..1]
      end
    end

    # DEL: Eliminate null-rule
    def transform_del
      loop do
        nullable = []
        @productions.filter { |p| p.null? && p.name != @start }.each do |p|
          nullable << p.name
          delete_production(p)
        end
        break if nullable.empty?

        @productions.each do |p|
          indices = []
          p.rhs.each_with_index { |z,i| indices << i if nullable.include?(z) }

          # Generate all possible omissions
          (1..indices.length).each do |n|
            indices.combination(n).each do |comb|
              rhs = p.rhs.clone
              comb.each do |i|
                rhs.delete_at(i)
                comb = comb.map { |j| j > i ? j - 1 : j }
              end
              add_production(p.name, *rhs, generated: p.generated?)
            end
          end
        end
      end
    end

    # UNIT: Eliminate unit rules
    def transform_unit
      loop do
        modified = false
        @productions.each do |p|
          next unless p.length == 1 && nonterminal?(p[0])

          modified = true
          delete_production(p)
          Array(self[p[0]]).each { |p2| add_production(p.name, *p2.rhs, generated: p.generated?) }
        end

        break unless modified
      end
    end

    def chomsky?
      @productions.each do |p|
        return false if p.length > 2
        return false if p.length == 2 && (!nonterminal?(p[0]) || !nonterminal?(p[1]))
        return false if p.length == 1 && !terminal?(p[0])
        return false if p.null? && p.name != @start
      end
      true
    end

    def chomsky
      return if chomsky?

      transform_start
      transform_term
      transform_bin
      transform_del
      transform_unit

      merge_duplicate_rules
    end

    def [](index)
      case index
      when Integer then @productions[index]
      when Range
        list = index.map { |i| self[i] }
        list.length <= 1 ? list.first : list
      when Production then @productions.filter { |p| p == index }.first
      else
        list = @productions.filter { |p| p.name == index }
        list.length <= 1 ? list.first : list
      end
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
      s = "% start: #{@start.nil? ? '?' : @start}\n"
      s += "% terminals:"
      @terminals.each { |z| s += " #{z}" }
      return s if @productions.empty?

      rows = []
      ([@start].concat @nonterminals.filter { |x| x != @start }).each do |x|
        next if self[x].nil?

        r = [x.to_s]
        Array(self[x]).each_with_index { |p,i| r << (p.null? ? 'ϵ' : p.rhs.join(' ')) }
        rows << r
      end

      ncols = rows.map(&:length).max
      col_widths = [*(0..ncols)].map { |i| rows.map { |r| r[i].to_s.length }.max }

      rows.each do |r|
        s += "\n#{r[0].ljust(col_widths[0])} -> "
        [*(1..r.length - 1)].each { |i| s += "#{i > 1 ? ' / ' : ''}#{r[i].ljust(col_widths[i])}" }
      end
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
        p.children.map { |c| add_production(rule.name, c) }
      else
        add_production(rule.name, p)
      end
    end

    def convert(*args)
      @branches = [{rhs: [], children: []}]

      args.each_with_index do |arg, i|
        @branches.length.times { |i| convert_step(arg, i) }
      end

      @branches
    end

    def convert_step(arg, branch)
      case arg
      when Alternation
        arg.children[1..].each do |c|
          @branches << { rhs: @branches[branch][:rhs].clone, children: [] }
          @branches[branch][:children] << @branches.length - 1
          convert_step(c, @branches.length - 1)
        end
        convert_step(arg.children.first, branch)
      when Concatenation
        arg.children.each do |c|
          @branches[branch][:children].each { |b| convert_step(c, b) }
          convert_step(c, branch)
        end
      when Optional
        @branches << { rhs: @branches[branch][:rhs].clone, children: [] }
        @branches[branch][:children] << @branches.length - 1
        convert_step(arg.children.first, @branches.length - 1)
      when Repeat
        impl_name = case arg.children.first
                    when Rule then arg.children.first.name
                    when Terminal then arg.children.first.name.nil? ? arg.children.first.match : arg.children.first.name
                    else
                      impl_name = unique_name(:RI)
                      backup = @branches.clone
                      add_production(impl_name, arg.children.first, generated: true)
                      @branches = backup
                      impl_name
                    end

        case arg.max
        when arg.min then @branches[branch][:rhs].concat [impl_name] * arg.min
        when Float::INFINITY
          name = unique_name(:R)
          backup = @branches.clone
          add_production(name, impl_name, name, generated: true)
          add_production(name, impl_name, generated: true)
          @branches = backup

          @branches[branch][:rhs].concat [impl_name] * arg.min
          @branches << { rhs: @branches[branch][:rhs].clone, children: [] }
          @branches[branch][:children] << @branches.length - 1
          @branches[@branches.length - 1][:rhs] << name
        else
          @branches[branch][:rhs].concat [impl_name] * arg.min
          (1..arg.max - arg.min).each do |i|
            @branches << { rhs: @branches[branch][:rhs].clone, children: [] }
            @branches[branch][:children] << @branches.length - 1
            @branches[@branches.length - 1][:rhs].concat [impl_name] * i
          end
        end
      when Rule then @branches[branch][:rhs] << arg.name
      when Terminal then @branches[branch][:rhs] << (arg.name.nil? ? arg.match : arg.name)
      else @branches[branch][:rhs] << arg
      end
    end

    def unique_name(basename)
      #return basename unless symbols.include?(basename)
      @unique_name_count ||= {}
      @unique_name_count[basename] ||= 1
      name = "#{basename}#{@unique_name_count[basename]}"
      name = name.to_sym if basename.is_a?(Symbol)
      @unique_name_count[basename] += 1
      while symbols.include?(name)
        name = "#{basename}#{@unique_name_count[basename]}"
        name = name.to_sym if basename.is_a?(Symbol)
        @unique_name_count[basename] += 1
      end
      name
    end
  end
end
