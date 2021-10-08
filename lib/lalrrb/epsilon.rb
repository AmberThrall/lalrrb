# frozen_string_literal: true

require_relative 'nonterminal'

module Lalrrb
  class Epsilon < Nonterminal
    def initialize
      super(:epsilon)
    end

    def to_s
      "ϵ"
    end

    def to_regex
      //
    end

    def to_svg
      g = SVG::Group.new(width: 100, height: 50)
      g << SVG::Ellipse.new(g.width / 2, g.height / 2, g.width / 2, g.height / 2, fill: 'none', stroke: 'black')
      g << SVG::Text.new(to_s, g.width / 2, g.height / 2, text_anchor: 'middle', dominant_baseline: 'middle')
    end
  end
end
