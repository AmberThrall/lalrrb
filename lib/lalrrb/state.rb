# frozen_string_literal: true

module Lalrrb
  class State
    attr_reader :items

    def initialize(*items)
      @items = items.flatten
    end

    def add(item)
      @items << item unless @items.include?(item)
      self
    end

    def kernel
      k = State.new
      @items.each { |i| k.add i if i.in_kernel? }
      k
    end

    def [](index)
      @items[index]
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

    def mostly_equal?(other)
      return false unless other.is_a?(State)

      other.items.each do |ji|
        match = false
        @items.each do |i|
          if i.production == ji.production && i.position == ji.position
            match = true
            break
          end
        end

        return false unless match
      end

      @items.each do |i|
        match = false
        other.items.each do |ji|
          if i.production == ji.production && i.position == ji.position
            match = true
            break
          end
        end

        return false unless match
      end

      true
    end

    def ==(other)
      return false unless other.is_a?(State)

      @items.each do |i|
        return false unless other.include?(i)
      end

      other.items.each do |i|
        return false unless include?(i)
      end

      true
    end

    def merge(other)
      other.items.each do |i|
        @items << i unless include?(i)
      end
    end

    def to_s(gap: 2, border: true)
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
