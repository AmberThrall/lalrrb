# frozen_string_literal: true

require_relative 'nonterminal'

module Lalrrb
  class Terminal < Nonterminal
    attr_accessor :name, :match

    def initialize(match, name: nil)
      super(:terminal)
      @name = name
      @match = match
    end

    def to_s
      return @name.to_s unless @name.nil?

      strs = Array(@match).map { |m| m.is_a?(Regexp) ? "/#{m.source}/" : m.to_s.dump }
      strs.length > 1 ? "(#{strs.join(' | ')})" : strs.first
    end

    def to_h
      { type: @type, name: @name, match: @match }
    end

    def to_regex
      alts = Array(match).map do |m|
        m.is_a?(Regexp) ? m : Regexp.new(Regexp.escape(m.to_s))
      end

      alts.length > 1 ? Regexp.new("(#{alts.map(&:source).join('|')})") : alts.first
    end

    def to_svg
      s = to_s
      g = SVG::Group.new(width: [100, s.length * 12].max, height: 50)
      g << SVG::Ellipse.new(g.width / 2, g.height / 2, g.width / 2, g.height / 2, fill: 'none', stroke: 'black')
      g << SVG::Text.new(s, g.width / 2, g.height / 2, text_anchor: 'middle', dominant_baseline: 'middle')
    end
  end
end
