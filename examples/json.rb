require_relative '../lib/lalrrb'


class Json
  class Grammar < Lalrrb::Grammar
    token(:NUMBER, /-?\d+(\.\d+)?([eE][+-]?\d+)?/)
    token(:STRING, /"(?:\\["\\\/bfnrt]|\\u[0-9A-Fa-f]{4}|[^"\\])*"/)
    token(:WS, /[\u0020\u000A\u000D\u0009]/) { toss }

    start(:json)
    rule(:json) { value }
    rule(:value) { object / array / STRING / NUMBER / 'true' / 'false' / 'null' }
    rule(:object) { ('{' >> members? >> '}') }
    rule(:members) { member >> (',' >> member).repeat }
    rule(:member) { STRING >> ':' >> value }
    rule(:array) { ('[' >> elements? >> ']') }
    rule(:elements) { value >> (',' >> value).repeat }
  end

  def initialize
    @parser = Lalrrb::Parser.new(Grammar)
  end

  def parse(text, **opts)
    opts[:symbolize_keys] ||= false
    root, log = @parser.parse(text)
    log.save(opts[:output_log]) unless opts[:output_log].to_s.empty?
    root.graphviz.output(png: opts[:output_graphviz]) unless opts[:output_graphviz].to_s.empty?
    root.pretty_print if opts[:print_tree]
    parse_value(root[:value], opts)
  end

  private

  def parse_value(node, opts)
    case node[0].name
    when :object then parse_object(node[0], opts)
    when :array then parse_array(node[0], opts)
    when :STRING then parse_string(node[0])
    when :NUMBER then parse_number(node[0])
    when 'true' then true
    when 'false' then false
    when 'null' then nil
    end
  end

  def parse_object(node, opts)
    hash = {}
    members = node[:members]
    return hash if members.nil?

    members = Array(members[:member])
    members.each do |member|
      key = parse_string(member[:STRING])
      value = parse_value(member[:value], opts)
      hash[opts[:symbolize_keys] ? key.to_sym : key] = value
    end

    hash
  end

  def parse_array(node, opts)
    array = []
    elements = node[:elements]
    return array if elements.nil?

    values = Array(elements[:value])
    values.each do |value|
      array << parse_value(value, opts)
    end

    array
  end

  def parse_string(node)
    node.value[1..-2]
  end

  def parse_number(node)
    as_f = node.value.to_f
    as_i = node.value.to_i
    return as_i if as_i.to_f == as_f

    as_f
  end
end

TEST_JSON = %(
  {"widget": {
      "debug": true,
      "window": {
          "title": "Sample Konfabulator Widget",
          "name": "main_window",
          "width": 500,
          "height": 500
      },
      "image": {
          "src": "Images/Sun.png",
          "name": "sun1",
          "hOffset": 250,
          "vOffset": 250,
          "alignment": "center"
      },
      "text": {
          "data": "Click Here",
          "size": 36,
          "style": "bold",
          "name": "text1",
          "hOffset": 250,
          "vOffset": 100,
          "alignment": "center",
          "onMouseUp": "sun1.opacity = (sun1.opacity / 100) * 90;"
      }
  }}
)

json = Json.new
pp json.parse(TEST_JSON, symbolize_keys: true)
