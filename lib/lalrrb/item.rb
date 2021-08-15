# frozen_string_literal: true

require_relative 'production'

module Lalrrb
  class Item
    attr_accessor :production, :position, :lookahead

    def initialize(production, position, lookahead = nil)
      @production = production
      @position = position
      @lookahead = lookahead
    end

    def to_s
      "(#{@production.to_s(position: @position)}, #{@lookahead})"
    end

    def next
      @production[@position]
    end

    def in_kernel?
      return true if @production.start_production? && at_start?
      return true unless at_start?

      false
    end

    def at_start?
      @position == 0
    end

    def at_end?
      @position == @production.length || self.next == :EOF
    end

    def shift
      copy = clone
      copy.position += 1 unless copy.at_end?
      copy
    end

    def ==(other)
      @production == other.production && @position == other.position && @lookahead == other.lookahead
    end
  end
end
