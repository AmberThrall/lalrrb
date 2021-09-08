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

  def self.create(name, text, parent: nil, benchmark: false)
    if parent.nil?
      parent = ""
      caller.each do |call|
        m = call.match(/`<module:(.+)>'/)
        break if m.nil? || m[1].nil?

        parent = "::#{m[1]}#{parent}"
      end
      parent = parent.empty? ? Object : eval(parent)
    end

    raise Error, "Object name #{name} already taken" if parent.const_defined?(name)

    g = nil
    p = nil
    if benchmark
      require 'benchmark'

      Benchmark.bm(10) do |bm|
        bm.report("grammar:") { g = ABNF.parse(text) }
        bm.report("parser:") { p = Parser.new(g) }
      end
    else
      g = ABNF.parse(text)
      p = Parser.new(g)
    end

    mod = Module.new
    mod.const_set(:Grammar, g)
    mod.const_set(:Parser, p)
    mod.const_set(:Lexer, p.lexer)
    mod.define_singleton_method(:parse) do |text, raise_on_error: true, return_steps: false|
      mod.const_get(:Parser).parse(text, raise_on_error: raise_on_error, return_steps: return_steps)
    end

    parent.const_set(name, mod)
    mod
  end
end
