# frozen_string_literal: true

require_relative 'concatenation'
require_relative 'alternation'
require_relative 'terminal'
require_relative 'optional'
require_relative 'repeat'

module Lalrrb
  module ClassExtensions
    def >>(other)
      case other
      when Concatenation then other >> Terminal.new(self)
      when Nonterminal then Concatenation.new(Terminal.new(self), other)
      when String, Regexp, Array then Concatenation.new(Terminal.new(self), Terminal.new(other))
      else raise Error, 'invalid value to the right of >>'
      end
    end

    def |(other)
      case other
      when Alternation then other | Terminal.new(self)
      when Nonterminal then Alternation.new(Terminal.new(self), other)
      when String, Regexp, Array then Alternation.new(Terminal.new(self), Terminal.new(other))
      else raise Error, 'invalid value to the right of |'
      end
    end

    def optional
      Optional.new(Terminal.new(self))
    end

    def repeat(min = 0, max = Float::INFINITY)
      Repeat.new(Terminal.new(self), min, max)
    end
  end
end

class String
  include Lalrrb::ClassExtensions
end

class Regexp
  include Lalrrb::ClassExtensions
end

class Array
  include Lalrrb::ClassExtensions
end
