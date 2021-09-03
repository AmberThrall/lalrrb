# frozen_string_literal: true

require_relative 'nonterminal'
require_relative 'terminal'

module Lalrrb
  class Rule < Nonterminal
    attr_reader :name

    def initialize(name, &block)
      super(:rule)
      @name = name
      @block = block
    end

    def to_s(expand: false)
      return "#{@name} -> #{production}" if expand

      @name.to_s
    end

    def to_h(expand: false)
      return { type: @type, name: @name, production: production.to_h} if expand
      { type: @type, name: @name, production: :hidden }
    end

    def production
      ret = @block.call
      return Terminal.new(ret) if ret.is_a?(String) || ret.is_a?(Regexp)

      ret
    end

    def search(type, expand: false)
      matches = super(type)
      matches.concat production.search(type) if expand
      matches
    end

    def to_svg(expand: false)
      if expand
        p = production.to_svg
        g = SVG::Group.new(width: p.width + 110, height: p.height)
        g << SVG::Ellipse.new(10, 50, 10, 10, fill: 'black')
        g << SVG::Line.new(10, 50, 50, 50)
        g << p.move(50, 25)
        g << SVG::Line.new(50 + p.width, 50, 90 + p.width, 50)
        g << SVG::Ellipse.new(100 + p.width, 50, 10, 10, fill: 'black')
        g
      else
        g = SVG::Group.new(width: [100, @name.to_s.length * 12].max, height: 50)
        g << SVG::Rect.new(0, 0, g.width, g.height, stroke: 'black', fill: 'none')
        g << SVG::Text.new(@name.to_s, g.width / 2, g.height / 2, text_anchor: 'middle', dominant_baseline: 'middle')
        g
      end
    end
  end
end
