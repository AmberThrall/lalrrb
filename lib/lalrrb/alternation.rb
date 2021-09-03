# frozen_string_literal: true

require_relative 'nonterminal'

module Lalrrb
  class Alternation < Nonterminal
    def initialize(*children)
      super(:alternation, *children)
    end

    def to_s
      @children.map(&:to_s).join(' / ')
    end

    def /(other)
      case other
      when Alternation then @children.concat other
      when Nonterminal then @children << other
      when Regexp, String then @children << Terminal.new(other)
      else raise Error, "Invalid value on rhs of /."
      end

      self
    end

    def to_svg
      gs = @children.map(&:to_svg)
      mg = SVG::Group.new(width: gs.map(&:width).max + 80, height: gs.map(&:height).sum + 25 * (gs.length - 1))
      mg << SVG::Path.new(SVG::Path.move_to(0, 25), SVG::Path.arc(10, 10, 0, 0, 1, 10, 35)) if gs.length > 1
      mg << SVG::Path.new(SVG::Path.move_to(mg.width - 10, 35), SVG::Path.arc(10, 10, 0, 0, 1, mg.width, 25)) if gs.length > 1
      y = 0
      last_y = 35
      gs.each do |g|
        x = mg.width / 2 - g.width / 2
        mg << SVG::Line.new(0, 25, x, 25) if y.zero?
        mg << SVG::Line.new(x + g.width, y + 25, mg.width, 25) if y.zero?
        mg << SVG::Path.new([
          SVG::Path.move_to(10, last_y),
          SVG::Path.vline(y + 15),
          SVG::Path.arc(10, 10, 0, 0, 0, 20, y+25),
          SVG::Path.hline(x)
        ]) if y > 0
        mg << SVG::Path.new([
          SVG::Path.move_to(x + g.width, y + 25),
          SVG::Path.hline(mg.width - 20),
          SVG::Path.arc(10, 10, 0, 0, 0, mg.width - 10, y + 15),
          SVG::Path.vline(last_y)
        ]) if y > 0
        mg << g.move(x, y)
        last_y = y if y > 0
        y += g.height + 25
      end
      mg
    end
  end
end
