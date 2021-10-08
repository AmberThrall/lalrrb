# frozen_string_literal: true

require_relative 'svg'

module Lalrrb
  class Nonterminal
    attr_accessor :type, :children

    def initialize(type, *children)
      @type = type
      @children = Array(children).flatten
    end

    def to_s
      @type.to_s
    end

    def to_h
      {
        type: @type,
        children: @children.map(&:to_h)
      }
    end

    def search(type)
      matches = []
      matches << self if @type == type

      @children.each { |child| matches.concat child.search(type) }

      matches
    end

    require_relative 'concatenation'
    require_relative 'alternation'
    require_relative 'optional'
    require_relative 'repeat'
    require_relative 'terminal'

    def >>(other)
      case other
      when Concatenation then other >> self
      when Nonterminal then Concatenation.new(self, other)
      when Regexp, String, Array then Concatenation.new(self, Terminal.new(other))
      else raise Error, "invalid value on rhs of >>"
      end
    end

    def |(other)
      case other
      when Alternation then other >> self
      when Nonterminal then Alternation.new(self, other)
      when Regexp, String, Array then Alternation.new(self, Terminal.new(other))
      else raise Error, "invalid value on rhs of |"
      end
    end

    def optional
      Optional.new(self)
    end

    def repeat(min = 0, max = Float::INFINITY)
      Repeat.new(self, min, max)
    end

    def *(int)
      repeat(int, int)
    end
  end
end
