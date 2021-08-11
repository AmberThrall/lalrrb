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
      return "#{@name} = #{production.to_s}" if expand
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
  end
end
