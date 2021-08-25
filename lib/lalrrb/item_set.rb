# frozen_string_literal: true

require_relative 'basic_grammar'
require_relative 'item'

module Lalrrb
  class ItemSet
    attr_reader :items

    def initialize(grammar, *items)
      @grammar = grammar
      @items = items.map{ |i| i.is_a?(Item) ? i : i.to_a }.flatten
    end

    def add(item)
      @items << item unless include?(item)
      self
    end

    def [](index)
      @items[index]
    end

    def closure
      set = self.clone

      loop do
        old_size = set.size

        set.items.each do |item|
          first_set = @grammar.first(*item.production.rhs[item.position + 1..], item.lookahead)

          Array(@grammar[item.next]).each do |p|
            first_set.each do |b|
              set.add Item.new(p, 0, b)
            end
          end
        end

        break if set.size == old_size
      end

      set
    end

    def goto(symbol)
      set = ItemSet.new(@grammar)
      @items.filter { |i| i.next == symbol }.each do |i|
        set.add i.shift
      end
      set.closure
    end

    def clear
      @items.clear
    end

    def empty?
      @items.empty?
    end

    def size
      @items.size
    end

    def include?(item)
      @items.include?(item)
    end

    def to_a
      @items
    end

    def core
      c = ItemSet.new(@grammar)
      @items.each { |i| c.add Item.new(i.production, i.position) }
      c
    end

    def ==(other)
      return false unless other.is_a?(ItemSet)
      return false unless size == other.size

      @items.each { |i| return false unless other.include? i }

      true
    end

    def merge(other)
      other.items.each { |i| add i }
    end

    def to_s(gap: 2, border: true)
      return "[]" if empty?

      ps = []
      ts = []
      @items.each do |i|
        p = i.production.to_s(position: i.position)
        t = i.lookahead.to_s
        if index = ps.find_index(p)
          ts[index] += ",#{t}"
        else
          ps << p
          ts << t
        end
      end

      ps_width = ps.map(&:length).max
      ts_width = ts.map(&:length).max
      width = ps_width + gap + ts_width
      s = border ? "┌#{'─' * width}┐\n" : ''
      (0..ps.length - 1).each { |i| s += "#{border ? '│' : ''}#{ps[i].ljust(ps_width)}#{' ' * gap}#{ts[i].rjust(ts_width)}#{border ? '│' : ''}\n" }
      s += "└#{'─' * width}┘" if border
      s
    end
  end
end
