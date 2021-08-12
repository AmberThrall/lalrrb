# frozen_string_literal: true

module Lalrrb
  class Production
    attr_reader :name, :rhs

    def initialize(name, *rhs)
      @name = name
      @rhs = rhs.flatten
    end

    def length
      @rhs.length
    end

    def <<(other)
      @rhs << other
    end

    def to_s(position: nil)
      s = "#{@name} ->"
      return "#{s} ϵ" if @rhs.empty?

      @rhs.each_with_index { |t,i| s += " #{position == i ? '•' : ''}#{t}" }
      s += '•' if position == @rhs.length
      s
    end
  end
end
