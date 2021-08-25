# frozen_string_literal: true

require 'ruby-graphviz'

module Lalrrb
  class ParseTree
    attr_accessor :data, :children
    attr_reader :parent

    def initialize(data, *children)
      if data.is_a?(ParseTree)
        @parent = nil
        @data = data.data
        @children = []
        data.children.each { |c| self << c }
      else
        @parent = nil
        @data = data
        @children = []
      end

      children.flatten.each { |c| self << c }
    end

    def subtree
      sub = ParseTree.new(@data)
      @children.each { |c| sub << c.subtree }
      sub
    end

    def root?
      @parent.nil?
    end

    def branch?
      @children.length.positive?
    end

    def leaf?
      @children.empty?
    end

    def sibling?(x)
      @parent == x.parent
    end

    def ancestor?(x)
      return true unless x == self
      return false if root?

      @parent.ancestor?(x)
    end

    def descendent?(x)
      return true unless x == self
      return false if leaf?

      @children.each { |c| return true if c.descendent?(x) }
      false
    end

    def root
      return self if root?

      @parent.root
    end

    def degree
      @children.length
    end

    def size
      root._size
    end

    def breadth
      @@breadth = 0
      root._breadth
    end

    def level
      return 0 if root?

      @parent.level + 1
    end

    def width(level = nil)
      @@width = 0
      root._width(level.nil? ? self.level : level, 0)
    end

    def [](term)
      matches = search(term, recursive: false, include_self: false)
      return matches.first if matches.length == 1

      matches
    end

    def <<(other)
      other = ParseTree.new(other) unless other.is_a?(ParseTree)
      return self if @children.include?(other)

      @children << other
      other.parent = self
      self
    end

    def search(*terms, recursive: true, include_self: true)
      matches = []

      terms.flatten.each do |term|
        nodes = include_self ? [self, @children].flatten : @children
        case term
        when ParseTree then matches << nodes.include?(term) ? term : nil
        when Integer then matches << @children[term]
        when String, Symbol
          matches.concat(nodes.filter do |c|
            c == term || c.name == term || (c.token? && c.value == term) || c.data == term
          end)
        when Range then matches.concat Range.to_a.map { |s| search(s, recursive: false, include_self: include_self) }
        end
      end

      matches = matches.flatten
      @children.each { |c| matches.concat Array(c.search(*terms, recursive: true, include_self: false)) } if recursive
      matches = matches.uniq
      matches.delete(nil)

      matches
    end

    def delete(keep_descendents: true)
      raise StandardError, "Cannot delete root node." if root?

      @children.each { |c| c.delete(keep_descendents: false) } unless keep_descendents
      @children.each { |c| @parent << c } if keep_descendents

      @parent.children.delete(self)
      @parent = nil
    end

    def simplify
      loop do
        new_children = @children.map { |c| c.simplify }.flatten
        break if new_children == @children

        @children = new_children
      end

      return @children if @data.is_a?(Production) && @data.generated?

      self
    end

    def parent=(node)
      return if @parent == node

      @parent.children.delete(self) unless @parent.nil?
      @parent = node
      @parent << self unless @parent.nil?
    end

    def production?
      @data.is_a?(Production)
    end

    def token?
      @data.is_a?(Token)
    end

    def name
      case @data
      when Production then @data.name
      when Token then @data.name
      end
    end

    def value
      case @data
      when Production then @children.map { |c| c.value }.join
      when Token then @data.value
      else @data.to_s
      end
    end

    def graphviz
      g = GraphViz.new(:G, type: :digraph)
      root._graphviz(g, nil, 0)
      g
    end

    def pretty_print(level = 0, spaces: 2, value_length: 10)
      print ['│', ' ' * spaces].join * [level - 1, 0].max
      print "└#{'─' * (spaces - 1)} " if level.positive?
      val = value.to_s
      val = "#{val[..value_length]...}" if val.length > value_length
      puts "#{name} (#{val})"
      @children.each { |c| c.pretty_print(level + 1, spaces: spaces, value_length: value_length) }
    end

    def to_h
      {
        data: @data,
        children: @children.map(&:to_h)
      }
    end

    protected

    def _breadth
      if leaf?
        @@breadth += 1
      else
        @children.each { |c| c._breadth }
        @@breadth
      end
    end

    def _size
      @children.map { |c| c._size }.sum + 1
    end

    def _width(level, current_level)
      @@width += 1 if current_level == level
      @children.each { |c| c._width(level, current_level + 1) } if current_level < level
      @@width
    end

    def _graphviz(g, parent, index)
      label, shape = case @data
                     when Production then [@data.name, :rectangle]
                     when Token then [@data.value, :circle]
                     else [@data.to_s, :circle]
                     end
      node = g.add_nodes(parent.nil? ? index.to_s : "#{parent.id}.#{index}", label: label, shape: shape)
      g.add_edges(parent, node) unless parent.nil?

      @children.each_with_index { |c, i| c._graphviz(g, node, i) }
    end
  end
end
