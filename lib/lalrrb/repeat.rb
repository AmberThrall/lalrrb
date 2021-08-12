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

    def to_svg
      g = @children.first.to_svg
      mg = SVG::Group.new(width: g.width + 40, height: g.height + 45)
      mg << g.move(20, 0)
      mg << SVG::Line.new(0, 25, 20, 25)
      mg << SVG::Line.new(g.width + 20, 25, g.width + 40, 25)
      mg << SVG::Path.new([
          SVG::Path.move_to(20, 25),
          SVG::Path.arc(10, 10, 0, 0, 0, 10, 35),
          SVG::Path.vline(g.height + 10),
          SVG::Path.arc(10, 10, 0, 0, 0, 20, g.height + 20),
          SVG::Path.hline(g.width + 20),
          SVG::Path.arc(10, 10, 0, 0, 0, g.width + 30, g.height + 10),
          SVG::Path.vline(35),
          SVG::Path.arc(10, 10, 0, 0, 0, g.width + 20, 25)
      ])
      if @min <= 0
        mg << SVG::Path.new(SVG::Path.move_to(0, 25), SVG::Path.arc(10, 10, 0, 0, 1, 10, 35))
        mg << SVG::Path.new(SVG::Path.move_to(g.width + 30, 35), SVG::Path.arc(10, 10, 0, 0, 1, g.width + 40, 25))
      end

      text = @max < Float::INFINITY ? @min == @max ? "#{@max} times" : "#{@min}-#{@max} times" : "#{@min}+ times"
      mg << SVG::Text.new(text, mg.width / 2, g.height + 20, font_size: 'small', text_anchor: 'middle', dominant_baseline: 'hanging')

      mg
    end
  end
end
