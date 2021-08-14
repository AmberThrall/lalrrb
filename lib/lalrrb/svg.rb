# frozen_string_literal: true

module Lalrrb
  module SVG
    class SVGObject
      attr_reader :type, :contents
      attr_accessor :attributes

      def initialize(type, contents = [], **attributes)
        @type = type
        @attributes = attributes
        @contents = contents
      end

      def <<(other)
        @contents << other
        self
      end

      def to_s(spaces: 2, indent: 0)
        s = ' ' * spaces * indent
        s += "<#{@type}"
        @attributes.each { |k,v| s += " #{k.to_s.gsub("_","-")}=\"#{v}\"" }
        return "#{s}/>" if @contents.empty?

        s += ">\r\n"
        @contents.each do |c|
          s += c.to_s(spaces: spaces, indent: indent + 1) if c.is_a?(SVGObject)
          s += "#{' ' * spaces * (indent + 1)}#{c.to_s}" unless c.is_a?(SVGObject)
          s += "\r\n"
        end
        s += "#{' ' * spaces * indent}</#{@type}>"
      end

      def x
        @attributes[:x].to_i
      end

      def y
        @attributes[:y].to_i
      end

      def width
        @attributes[:width]
      end

      def height
        @attributes[:height]
      end
    end

    class Root < SVGObject
      def initialize
        super(:svg, [], xmlns: "http://www.w3.org/2000/svg")
      end

      def save(filename)
        f = File.open(filename, 'w')
        f.puts to_s
        f.close
      end
    end

    class Rect < SVGObject
      def initialize(x, y, width, height, **attributes)
        super(:rect, [], x: x, y: y, width: width, height: height, **attributes)
      end
    end

    class Text < SVGObject
      def initialize(text, x, y, **attributes)
        text = text.gsub("<", "&lt;")
        text = text.gsub(">", "&gt;")
        super(:text, [text], x: x, y: y, **attributes)
      end
    end

    class Group < SVGObject
      def initialize(x = 0, y = 0, **attributes)
        super(:g, [], **attributes)
        move(x, y)
      end

      def move(x, y)
        @x = x
        @y = y
        @attributes[:x] = @x
        @attributes[:y] = @y
        @attributes[:transform] = "translate(#{@x} #{@y})"
        self
      end

      def x=(x)
        move(x, @y)
      end

      def y=(y)
        move(@x, y)
      end
    end

    class Path < SVGObject
      def initialize(*d, color: 'black', **attributes)
        attributes[:stroke] ||= color
        attributes[:fill] ||= 'transparent'
        super(:path, [], d: d.flatten.map(&:to_s).join(' '), **attributes)
      end

      def self.move_to(x, y, relative: false)
        "#{relative ? 'm' : 'M'} #{x} #{y}"
      end

      def self.line(x, y, relative: false)
        "#{relative ? 'l' : 'L'} #{x} #{y}"
      end

      def self.hline(x, relative: false)
        "#{relative ? 'h' : 'H'} #{x}"
      end

      def self.vline(y, relative: false)
        "#{relative ? 'v' : 'V'} #{y}"
      end

      def self.close_path
        "Z"
      end

      def self.cubic(x1, y1, x2, y2, x, y, relative: false)
        "#{relative ? 'c' : 'C'} #{x1} #{y1}, #{x2} #{y2}, #{x} #{y}"
      end

      def self.cubic_s(x2, y2, x, y, relative: false)
        "#{relative ? 's' : 'S'} #{x2} #{y2}, #{x} #{y}"
      end

      def self.quadratic(x1, y1, x, y, relative: false)
        "#{relative ? 'q' : 'Q'} #{x1} #{y1}, #{x} #{y}"
      end

      def self.quadratic_s(x, y, relative: false)
        "#{relative ? 't' : 'T'} #{x} #{y}"
      end

      def self.arc(rx, ry, x_axis_rotation, large_arc_flag, sweep_flag, x, y, relative: false)
        "#{relative ? 'a' : 'A'} #{rx} #{ry} #{x_axis_rotation} #{large_arc_flag} #{sweep_flag} #{x} #{y}"
      end
    end

    class Line < SVGObject
      def initialize(x1, y1, x2, y2, color = 'black', **attributes)
        attributes[:stroke] ||= color
        attributes[:fill] ||= 'transparent'
        super(:path, [], d: "M#{x1} #{y1} L #{x2} #{y2}", **attributes)
      end
    end

    class Ellipse < SVGObject
      def initialize(cx, cy, rx, ry, **attributes)
        super(:ellipse, [], cx: cx, x: cx - rx, cy: cy, y: cy - ry, rx: rx, width: cx + rx, ry: ry, height: cy + ry, **attributes)
      end
    end
  end
end
