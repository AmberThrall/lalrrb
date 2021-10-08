# frozen_string_literal: true

require_relative 'basic_grammar'
require_relative 'item'

module Lalrrb
  class ItemSet
    attr_reader :items

    def initialize(grammar, *items)
      @grammar = grammar
      @items = []
      items.map { |i| i.is_a?(Item) ? i : i.to_a }.flatten.each { |i| add i }
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
      last_pos = 0

      loop do
        old_size = set.size

        set.items[last_pos..].each do |item|
          first_set = @grammar.first(*item.production.rhs[item.position + 1..], item.lookahead)

          Array(@grammar[item.next]).each do |p|
            first_set.each do |b|
              set.add Item.new(p, 0, b)
            end
          end
        end

        last_pos = old_size
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

    def each(&block)
      @items.each(&block)
    end

    def each_with_index(&block)
      @items.each_with_index(&block)
    end

    def map(&block)
      @items.map(&block)
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

    def pretty_print
      ps = []
      ts = []
      @items.each do |i|
        p = i.production.to_s(position: i.position)
        t = i.lookahead == :EOF ? '$' : i.lookahead.to_s
        t = '","' if t == ','
        if index = ps.find_index(p)
          ts[index] += ",#{t}"
        else
          ps << p
          ts << t
        end
      end

      if ps.empty?
        puts "[]"
      elsif ps.length == 1
        puts "[(#{ps.first}, #{ts.first})]"
      else
        ps_width = ps.map(&:length).max
        ts_width = ts.map(&:length).max
        puts "["
        (0..ps.length - 1).each do |i|
          puts "  (#{(ps[i]+',').ljust(ps_width+1)} #{ts[i].ljust(ts_width)})#{i == ps.length - 1 ? '' : ','}"
        end
        puts "]"
      end
    end
  end
end
