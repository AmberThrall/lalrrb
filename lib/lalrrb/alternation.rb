# frozen_string_literal: true

require_relative 'nonterminal'

module Lalrrb
  class Alternation < Nonterminal
    def initialize(*children)
      super(:alternation, *children)
    end

    def to_s
      @children.map(&:to_s).map { |s| s.include?(' ') ? "(#{s})" : s }.join(' / ')
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
  end
end
