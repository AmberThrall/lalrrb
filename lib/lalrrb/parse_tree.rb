# frozen_string_literal: true

require 'ruby-graphviz'

module Lalrrb
  class ParseTree
    attr_reader :data, :children, :parent

    def initialize(data, *children)
      @parent = nil
      @data = data
      @children = []
      children.flatten.each { |c| self << c }
    end

    def root?
      @parent.nil?
    end

    def leaf?
      @children.empty?
    end

    def <<(other)
      other = ParseTree.new(other) unless other.is_a?(ParseTree)
      return self if @children.include?(other)

      @children << other
      other.parent = self
      self
    end

    def remove_child(child)
      @children.delete(child)
    end

    def parent=(node)
      return if @parent == node

      @parent&.remove_child(self)
      @parent = node
      @parent << self
    end

    def graphviz(g = nil, parent = nil, index = 0)
      g = GraphViz.new(:G, type: :digraph) if g.nil?

      label = case @data
              when Production then @data.name
              when Token then @data.value
              else @data.to_s
              end
      shape = leaf? ? :circle : :rectangle
      node = g.add_nodes(parent.nil? ? index.to_s : "#{parent.id}.#{index}", label: label, shape: shape)
      g.add_edges(parent, node) unless parent.nil?

      @children.each_with_index { |c, i| c.graphviz(g, node, i) }

      g
    end

    def to_h
      {
        data: @data,
        children: @children.map(&:to_h)
      }
    end
  end
end
