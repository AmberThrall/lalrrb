# frozen_string_literal: true

module Lalrrb
  class Action
    attr_reader :type, :arg

    def initialize(type, arg)
      @type = type
      @arg = arg
    end

    def to_s
      case @type
      when :accept then "acc"
      when :shift then "s#{@arg}"
      when :goto then arg.to_s
      when :reduce then "r#{@arg}"
      when :error then "err"
      else "#{@type}#{@arg}"
      end
    end

    def self.accept
      new(:accept, -1)
    end

    def self.shift(state)
      new(:shift, state)
    end

    def self.goto(state)
      new(:goto, state)
    end

    def self.reduce(production)
      new(:reduce, production)
    end

    def self.error(msg)
      new(:error, msg)
    end
  end
end
