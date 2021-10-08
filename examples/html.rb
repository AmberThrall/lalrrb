# frozen_string_literal: true

require 'lalrrb'
require 'net/http'
require 'benchmark'

module HTML
  Benchmark = Lalrrb::BenchmarkTimes.new

  Parser = Lalrrb.create(File.read(File.join(__dir__, "html.grammar")),
    benchmark: true, benchmark_show_total: false, benchmark_times: Benchmark)

  class Element
    attr_reader :id, :attributes

    def initialize(id, *cont, **attr)
      @id = id
      @content = cont
      @attributes = attr
    end

    def [](index)
      return content[index] if index.is_a?(Integer)
      return index.map { |i| self[i] } if index.is_a?(Range)

      search(index)
    end

    def rsearch(id, **attr)
      matches = Array(search(id, **attr))
      @content.each { |c| matches.concat Array(c.rsearch(id, **attr)) if c.is_a?(Element) }
      matches.length > 1 ? matches : matches.first
    end

    def search(id, **attr)
      matches = []
      @content.each do |c|
        next unless c.is_a?(Element)
        next unless c.id.to_s.downcase == id.to_s.downcase

        matches << c
        attr.each do |k,v|
          next if c.attributes[k] == v

          matches.pop
          break
        end
      end

      matches.length > 1 ? matches : matches.first
    end

    def content
      @content.length > 1 ? @content : @content.first
    end

    def to_h
      cont = @content.map { |c| c.is_a?(Element) ? c.to_h : c }
      { id: @id, attributes: @attributes, content: cont.length > 1 ? cont : cont.first }
    end

    def to_s
      s = "<#{@id}"
      @attributes.each { |k,v| s += " #{k}=\"#{v}\"" }
      return "#{s}/>" if @content.empty?
      return "#{s}>#{@content.first}</#{@id}>" if @content.length == 1 && @content.first.to_s.lines.length <= 1

      s += ">\n"
      @content.each do |c|
        cs = c.to_s
        next if cs.strip.empty?

        on_newline = s[-1] == "\n"
        s += "  " if on_newline

        lines = cs.lines
        lines.delete_at(0) while lines[0].strip.empty?
        lines.delete_at(-1) while lines[-1].strip.empty?
        if lines.length > 1
          s += "\n" unless on_newline
          s += "#{lines.map { |l| "  #{l}" }.join("\n")}\n"
        else
          s += lines.join
        end
      end
      s += "\n" unless s[-1] == "\n"

      s += "</#{@id}>"
      s
    end
  end

  class ElementRoot < Element
    def initialize(*content)
      super(nil, *content)
    end

    def to_h
      cont = @content.map { |c| c.is_a?(Element) ? c.to_h : c }
      cont.length > 1 ? cont : cont.first
    end

    def to_s(spaces = 2, indent = 0)
      return "" if @content.empty?

      s = super
      f = s.rindex("<")
      s[2..f-1]
    end
  end

  class ElementText < Element
    def to_s
      @content.first.to_s
    end

    def to_h
      h = super
      h.delete(:attributes)
      h
    end
  end

  class << self
    def parse(html)
      root = HTML::Parser.parse(html)

      content = root.children.map do |n|
        case n.name
        when :SCRIPTLET, :XML, :DTD then ElementText.new(n.name, n.value)
        when :htmlElements
          n.children.map do |n2|
            case n2.name
            when :htmlComment then ElementText.new(n2[0].name, n2[0].value)
            when :htmlElement then element(n2)
            end
          end
        end
      end.flatten

      ElementRoot.new(*content)
    end

    private

    def element(node)
      node = node[0]

      case node.name
      when :SCRIPTLET then ElementText.new(node.name, node.value)
      when :tag
        tag_names = Array(node[:TAG_NAME]).map { |tn| tn.value.downcase }
        if tag_names.length == 2 && tag_names[0] != tag_names[1]
          raise StandardError, "tag name in close tag doesn't match open tag (open: #{tag_names[0]}, close: #{tag_names[1]})"
        end
        name = tag_names.first.to_sym

        attr = {}
        Array(node[:htmlAttribute]).each { |n| attr[n[:TAG_NAME].value.to_sym] = attvalue(n[:ATTVALUE_VALUE]) }

        cont = Array(node[:htmlContent]).map { |n| content(n) }

        Element.new(name, *cont, **attr)
      when :script, :style then Element.new(node.name, node[1].value[..node[1].value.rindex('<')-1])
      end
    end

    def attvalue(node)
      return true if node.nil?

      value = node.value.strip
      if value[0] == value[-1] && (value[0] == '"' || value[0] == '\'')
        value = "\"#{value[1..-2].gsub("\\'",'\'').gsub('"',"\\\"")}\"" if value[0] == '\''
        value.undump
      else
        value
      end
    rescue RuntimeError
      node.value.strip
    end

    def content(node)
      node = node[0]

      case node.name
      when :htmlElement then element(node)
      when :HTML_TEXT, :CDATA then ElementText.new(node.name, node.value)
      when :htmlComment then ElementText.new(node[0].name, node[0].value)
      end
    end
  end
end

HTML::Parser::Grammar.syntax_diagram.save("html-syntax-diagram.svg")

source = ""
html = nil

Benchmark.benchmark("", 10, Benchmark::FORMAT, "total") do |bm|
  tf = bm.report("fetch") do
    response = Net::HTTP.get_response(URI("https://en.wikipedia.org/wiki/LALR_parser"))
    encoding = "ISO-8859-1"
    encoding = response.header['content-type'].split("=").last if response.header['content-type'].to_s.include?('charset')
    source = response.body.force_encoding(encoding).encode("UTF-8")
  end
  tp = bm.report("parse") { html = HTML.parse(source) }
  [HTML::Benchmark.total + tf + tp]
end

#HTMLParser.lexer.tokenize(source, debug: true)
html = html.rsearch(:div, id: "mw-content-text")
html = html.search(:div, class: "mw-parser-output")
html = html[:p].first
puts "\n============\n\n"
puts html
puts "\n============\n\n"
pp html.to_h
