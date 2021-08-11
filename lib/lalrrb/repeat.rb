# frozen_string_literal: true

require_relative 'nonterminal'

module Lalrrb
  class Repeat < Nonterminal
    def initialize(child, min = 0, max = Float::INFINITY)
      super(:repeat, child)
      @min = min
      @max = max
    end

    def to_s
      s = @children.first.to_s
      "#{@min.positive? ? @min : ''}*#{@max < Float::INFINITY ? @max : ''}#{s.include?(' ') ? "(#{s})" : s}"
    end

    def to_h
      {
        type: @type,
        min: @min,
        max: @max,
        term: @children.first.to_h
      }
    end
  end
end
