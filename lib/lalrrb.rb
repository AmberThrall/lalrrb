# frozen_string_literal: true

require 'benchmark'
require_relative 'lalrrb/table'
require_relative 'lalrrb/basic_grammar'
require_relative 'lalrrb/grammar'
require_relative 'lalrrb/parser'
require_relative 'lalrrb/metasyntax'
require_relative 'lalrrb/version'

module Lalrrb
  class Error < StandardError; end

  class BenchmarkTimes < Hash
    def []=(index, time)
      raise Error, "unexpected type #{time.class}; expected type Benchmark::Tms" unless time.is_a?(Benchmark::Tms)
      super(index, time)
    end

    def total
      t = Benchmark::Tms.new
      each { |_,v| t += v }
      t
    end

    def pretty_print(caption = Benchmark::CAPTION, label_width = nil, format = Benchmark::FORMAT)
      longest_label_length = map { |k,_| k.to_s.length }.max
      label_width = [label_width.to_i, longest_label_length].max

      args = [caption, label_width, format]
      args.concat map { |k,_| k.to_s }
      args << "total"
      Benchmark.benchmark(*args) do
        [map { |_,t| t }, total].flatten
      end
    end
  end

  def self.grammar(text, **opts)
    opts[:benchmark_times] = BenchmarkTimes.new unless opts[:benchmark_times].is_a?(BenchmarkTimes)
    opts[:benchmark] = false if opts[:benchmark].nil?
    opts[:benchmark_format] ||= "%n: #{Benchmark::FORMAT}"

    if opts[:benchmark]
      g = nil
      opts[:benchmark_times]["grammar"] = Benchmark.measure("grammar") { g = Metasyntax.parse(text) }
      puts opts[:benchmark_time].format(opts[:benchmark_format]) unless opts[:benchmark_format].to_s.empty?
      opts.each { |name, value| g.set_option(name, value) if g.options.keys.include?(name) }
      g
    else
      g = Metasyntax.parse(text)
      opts.each { |name, value| g.set_option(name, value) if g.options.keys.include?(name) }
      g
    end
  end

  def self.create(arg, **opts)
    g = arg
    p = nil
    opts[:benchmark_times] = BenchmarkTimes.new unless opts[:benchmark_times].is_a?(BenchmarkTimes)
    opts[:benchmark] = false if opts[:benchmark].nil?
    opts[:benchmark_caption] ||= Benchmark::CAPTION
    opts[:benchmark_label_width] ||= 10
    opts[:benchmark_format] ||= Benchmark::FORMAT
    opts[:benchmark_show_total] = true if opts[:benchmark_show_total].nil?

    if opts[:benchmark]
      benchmark_args = [opts[:benchmark_caption], opts[:benchmark_label_width], opts[:benchmark_format]]
      benchmark_args << "total" if opts[:benchmark_show_total]
      Benchmark.benchmark(*benchmark_args) do |bm|
        opts[:benchmark_times]["grammar"] = bm.report("grammar") do
          g = Metasyntax.parse(arg) if arg.is_a?(String)
          opts.each { |name, value| g.set_option(name, value) if g.options.keys.include?(name) }
        end

        opts2 = opts.clone
        opts2[:benchmark_caption] = ""
        opts2[:benchmark_show_total] = false
        p = Parser.new(g, **opts2)

        [opts[:benchmark_times].total] if opts[:benchmark_show_total]
      end
    else
      g = Metasyntax.parse(arg) if arg.is_a?(String)
      opts.each { |name, value| g.set_option(name, value) if g.options.keys.include?(name) }
      p = Parser.new(g)
    end

    mod = Module.new
    mod.const_set(:Grammar, g)
    mod.const_set(:Parser, p)
    mod.const_set(:Lexer, p.lexer)
    mod.define_singleton_method(:parse) do |text, **options|
      mod.const_get(:Parser).parse(text, **options)
    end

    mod
  end
end
