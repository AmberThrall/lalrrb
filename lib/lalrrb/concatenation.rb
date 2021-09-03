# frozen_string_literal: true

require_relative 'nonterminal'
require_relative 'terminal'

module Lalrrb
  class Concatenation < Nonterminal
    def initialize(*children)
      super(:concatenation, *children)
    end

    def to_s
      @children.map { |s| s.is_a?(Alternation) ? "(#{s})" : s.to_s }.join(' ')
    end

    def >>(other)
      case other
      when Concatenation then @children.concat other
      when Nonterminal then @children << other
      when Regexp, String then @children << Terminal.new(other)
      else raise Error, "Invalid value on rhs of >>."
      end

      self
    end

    def to_svg
      gs = @children.map(&:to_svg)
      mg = SVG::Group.new(width: gs.map(&:width).sum + 40 * (gs.length - 1), height: gs.map(&:height).max)
      x = 0
      gs.each do |g|
        mg << SVG::Line.new(x, 25, x + 40, 25) if x.positive?
        x += 40 if x.positive?
        mg << g.move(x, 0)
        x += g.width
      end
      mg
    end
  end
end
