# frozen_string_literal: true

require_relative 'production'

module Lalrrb
  class Item
    attr_accessor :production, :position, :lookahead

    def initialize(production, position, lookahead)
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

    def ==(other)
      @production == other.production && @position == other.position && @lookahead == other.lookahead
    end
  end
end
