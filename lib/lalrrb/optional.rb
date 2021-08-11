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
  end
end
