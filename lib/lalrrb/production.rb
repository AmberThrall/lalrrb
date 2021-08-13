# frozen_string_literal: true

module Lalrrb
  class Production
    attr_reader :name, :rhs

    def initialize(name, *rhs)
      @name = name
      @rhs = rhs.flatten
      @rhs.delete_if { |r| r.to_s.empty? }
    end

    def length
      @rhs.length
    end

    def <<(other)
      @rhs << other
    end

    def [](index)
      @rhs[index]
    end

    def []=(index, value)
      @rhs[index] = value
    end

    def null?
      return @rhs.empty?
    end

    def to_s(position: nil)
      s = "#{@name} ->"
      return "#{s} ϵ" if null?

      @rhs.each_with_index { |t,i| s += " #{position == i ? '•' : ''}#{t}" }
      s += '•' if position == @rhs.length
      s
    end

    def ==(other)
      @name == other.name && @rhs == other.rhs
    end
  end
end
