# frozen_string_literal: true

require_relative 'lalrrb/table'
require_relative 'lalrrb/basic_grammar'
require_relative 'lalrrb/grammar'
require_relative 'lalrrb/parser'
require_relative 'lalrrb/class_extensions'
require_relative 'lalrrb/abnf'
require_relative 'lalrrb/version'

module Lalrrb
  class Error < StandardError; end

  def self.create(name, text)
    raise Error, "Object name '#{name}' already taken" if Object.const_defined?(name)

    Object.const_set(name, Module.new)
    obj = eval("#{name}")
    g = ABNF.parse(text)
    p = Parser.new(g)

    obj.define_singleton_method(:grammar) { g }
    obj.define_singleton_method(:parser) { p }
    obj.define_singleton_method(:lexer) { parser.lexer }
    obj.define_singleton_method(:parse) do |text, raise_on_error: true, return_steps: false|
      parser.parse(text, raise_on_error: raise_on_error, return_steps: return_steps)
    end
    obj
  end
end
