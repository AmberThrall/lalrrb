# frozen_string_literal: true

require 'ruby-graphviz'
require_relative 'table'

module Lalrrb
  class FSM
    attr_accessor :start

    def initialize
      @states = {}
      @edges = []
      @start = nil
    end

    def alphabet
      @edges.map { |e| e[:condition] }.uniq
    end

    def state(id = nil, accept: false)
      id ||= @states.length
      id = id.to_s
      @start = id if @start.nil?

      @states[id] = accept
      id
    end

    def edge(from, to, condition = "")
      @edges << { from: from, to: to, condition: condition }
    end

    def graphviz
      g = GraphViz.new(:G, type: :digraph, rankdir: :LR)

      @states.each do |id, accept|
        g.add_nodes(id, label: graphviz_label(id), shape: accept ? :doublecircle : :circle)
      end

      @edges.each { |e| g.add_edges(e[:from], e[:to], label: graphviz_label(e[:condition])) }

      g.add_nodes("starting_arrow", label: "", shape: :circle, width: 0.01)
      g.add_edges("starting_arrow", @start)

      g
    end

    def table
      table = Table.new
      @states.each do |id, _|
        hash = {}
        @edges.filter { |e| e[:from] == id }.each { |e| hash[graphviz_label(e[:condition])] = e[:to] }
        table.add_row(hash, label: id)
      end

      table
    end

    def parse(text)
      try(text, @start)
    end

    private

    def try(text, state)

    end

    def graphviz_label(label)
      return "/#{label.source}/" if label.is_a?(Regexp)
      label = label.to_s
      return "ϵ" if label.empty?
      return "\"#{label}\"" if label.strip.empty?
      label.gsub("\\", "\\\\\\")
    end
  end
end
