# frozen_string_literal: true

module Lalrrb
  class State
    attr_reader :items

    def initialize(*items)
      @items = items.flatten
    end

    def <<(item)
      @items << item unless item.nil? || @items.include?(item)
      self
    end

    def [](index)
      @items[index]
    end

    def length
      @items.length
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

    def merge(other)
      other.items.each do |i|
        items << i unless include?(i)
      end
    end

    def ==(other)
      return false if !other.is_a?(State) || other.length != length

      other.items.each do |i|
        return false unless include?(i)
      end

      true
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
