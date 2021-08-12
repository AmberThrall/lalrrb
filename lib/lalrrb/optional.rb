# frozen_string_literal: true

require_relative 'nonterminal'

module Lalrrb
  class Optional < Nonterminal
    def initialize(child)
      super(:optional, child)
    end

    def to_s
      "[#{@children.first.to_s}]"
    end

    def to_h
      {
        type: @type,
        term: @children.first.to_h
      }
    end

    def to_svg
      g = @children.first.to_svg
      if @children.first.is_a?(Alternation) && @children.first.children.length > 1
        g << SVG::Path.new([
          SVG::Path.move_to(10, 35),
          SVG::Path.vline(g.height + 25),
          SVG::Path.arc(10, 10, 0, 0, 0, 20, g.height + 35),
          SVG::Path.hline(g.width - 20),
          SVG::Path.arc(10, 10, 0, 0, 0, g.width - 10, g.height + 25),
          SVG::Path.vline(35)
        ])
        g.attributes[:height] += 45
        return g
      end

      mg = SVG::Group.new(width: g.width + 40, height: g.height + 30)
      mg << g.move(20, 0)
      mg << SVG::Line.new(0, 25, 20, 25)
      mg << SVG::Line.new(g.width + 20, 25, g.width + 40, 25)
      mg << SVG::Path.new([
          SVG::Path.move_to(0, 25),
          SVG::Path.arc(10, 10, 0, 0, 1, 10, 35),
          SVG::Path.vline(g.height + 10),
          SVG::Path.arc(10, 10, 0, 0, 0, 20, g.height + 20),
          SVG::Path.hline(g.width + 20),
          SVG::Path.arc(10, 10, 0, 0, 0, g.width + 30, g.height + 10),
          SVG::Path.vline(35),
          SVG::Path.arc(10, 10, 0, 0, 1, g.width + 40, 25)
      ])
      mg
    end
  end
end
