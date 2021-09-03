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

    def merge_duplicate_rules(generated_only: false)
      loop do
        # Get the set of duplicates
        duplicates = {}
        @nonterminals.each do |x|
          px = Array(self[x])
          duplicates[x] = []

          next unless duplicates.filter { |_,v| v.include?(x) }.empty?
          next if generated_only && px.filter { |p| p.generated? }.length != px.length

          @nonterminals.each do |y|
            next if y == x

            py = Array(self[y])
            next unless px.length == py.length
            next if generated_only && py.filter { |p| p.generated? }.length != py.length

            duplicates[x] << y
            px.each do |p|
              matched_production = nil

              py.each do |q|
                next unless p.length == q.length

                match = true
                p.length.times do |i|
                  unless p[i] == q[i] || (p[i] == x && q[i] == y)
                    match = false
                    break
                  end
                end

                if match
                  matched_production = q
                  break
                end
              end

              if matched_production.nil?
                duplicates[x].delete(y)
                break
              end

              py.delete(matched_production)
            end
          end
        end
        duplicates.delete_if { |x,v| v.empty? }
        break if duplicates.empty?

        # Remove duplicates keeping the first one.
        duplicates.each do |x,v|
          v.each do |y|
            duplicates.delete(y)
            replace_all(y, x) # Replace all instances of y with x
            delete_rule(y)
          end
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
      data = { branches: [{ rhs: [], children: [] }], repeats: {}, repeat_impls: {} }

      args.each do |arg|
        convert2(arg, 0, data)
      end

      data[:branches].each_with_index do |b,i|
        next if b.nil?

        data[:branches][i + 1..].each_with_index do |b2,j|
          next if b2.nil?

          data[:branches][j] = nil if b[:rhs] == b2[:rhs]
        end
      end
      data[:branches].delete(nil)

      data[:branches].map { |branch| branch[:rhs] }
    end

    def convert2(arg, cur_branch, data)
      data[:branches][cur_branch][:children].each { |c| convert2(arg, c, data) }

      case arg
      when Alternation
        new_branches = arg.children.map.with_index do |c,i|
          if i == 0
            cur_branch
          else
            data[:branches] << { rhs: data[:branches][cur_branch][:rhs].clone, children: [] }
            data[:branches].length - 1
          end
        end

        arg.children.each_with_index { |c,i| convert2(c, new_branches[i], data) }
        new_branches.filter { |b| b != cur_branch }.each { |b| data[:branches][cur_branch][:children] << b }
      when Concatenation then arg.children.each { |c| convert2(c, cur_branch, data) }
      when Optional
        data[:branches] << { rhs: data[:branches][cur_branch][:rhs].clone, children: []}
        data[:branches][cur_branch][:children] << data[:branches].length - 1
        convert2(arg.children.first, data[:branches].length - 1, data)
      when Repeat
        impl = data[:repeat_impls][arg.children.first.to_s]
        if impl.nil?
          impl = case arg.children.first
                 when Rule then arg.children.first.name
                 when Terminal then arg.children.first.name.nil? ? arg.children.first.match : arg.children.first.name
                 when Alternation, Concatenation, Optional, Repeat
                   name = unique_name(:I)
                   add_production(name, arg.children.first, generated: true)
                   name
                 else arg.children.first
                 end
          data[:repeat_impls][arg.children.first.to_s] = impl
        end

        case arg.max
        when arg.min then ret.concat [impl] * arg.min
        when Float::INFINITY
          name = data[:repeats][arg.children.first.to_s]
          if name.nil?
            name = unique_name(:R)
            add_production(name, impl, name, generated: true)
            add_production(name, impl, generated: true)
            data[:repeats][arg.children.first.to_s] = name
          end

          data[:branches][cur_branch][:rhs].concat [impl] * arg.min
          data[:branches] << { rhs: data[:branches][cur_branch][:rhs].clone, children: []}
          data[:branches][cur_branch][:children] << data[:branches].length - 1
          data[:branches][data[:branches].length - 1][:rhs] << name
        else
          data[:branches][cur_branch][:rhs].concat [impl] * arg.min
          (1..arg.max - arg.min).each do |i|
            data[:branches] << { rhs: data[:branches][cur_branch][:rhs].clone, children: []}
            data[:branches][cur_branch][:children] << data[:branches].length - 1
            data[:branches][data[:branches].length - 1][:rhs].concat [impl] * i
          end
        end
      when Rule then data[:branches][cur_branch][:rhs] << arg.name
      when Terminal then data[:branches][cur_branch][:rhs] << (arg.name.nil? ? arg.match : arg.name)
      else data[:branches][cur_branch][:rhs] << arg
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
