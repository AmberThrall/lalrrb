# frozen_string_literal: true

require_relative 'nonterminal'

module Lalrrb
  class Terminal < Nonterminal
    attr_reader :match, :name

    def initialize(match, name: nil)
      super(name.nil? ? :terminal : :token)
      @name = name
      @match = match
    end

    def to_s
      return @name.to_s unless @name.nil?
      return "/#{@match.source}/" if @match.is_a?(Regexp)

      "\"#{@match.to_s.gsub("\\", "\\\\\\").gsub("\"", "\\\"")}\""
    end

    def to_h
      return { type: @type, match: @match } if @name.nil?
      { type: @type, name: @name, match: @match }
    end

    def to_svg
      s = to_s
      g = SVG::Group.new(width: [100, s.length * 12].max, height: 50)
      g << SVG::Ellipse.new(g.width / 2, g.height / 2, g.width / 2, g.height / 2, fill: 'none', stroke: 'black')
      g << SVG::Text.new(s, g.width / 2, g.height / 2, text_anchor: 'middle', dominant_baseline: 'middle')
    end
  end
end
