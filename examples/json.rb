# frozen_string_literal: true

require 'lalrrb'

module Json
  Grammar = Lalrrb.create(%(
    token NUMBER : "-"? DIGITS FRACTION? EXPONENT? ;
    fragment FRACTION : "." DIGITS ;
    fragment EXPONENT : [eE] [+-]? DIGITS ;
    fragment DIGITS : [0-9]+ ;

    token STRING_START : '"' -> more, push_mode(STR) ;
    token(STR) STRING_ESCAPE : '\\\\' . -> more ;
    token(STR) STRING_CHAR : [^"\\\\]+ -> more ;
    token(STR) STRING : '"' -> pop_mode ;

    token WSP
      : '\\u0020'
      | '\\u000A'
      | '\\u000D'
      | '\\u0009'
      -> skip ;

    options { start = json; }
    json : value ;
    value
      : object
      | array
      | STRING
      | NUMBER
      | 'true'
      | 'false'
      | 'null'
      ;
    object : '{' members? '}' ;
    members : member (',' member)* ;
    member : STRING ':' value ;
    array : '[' elements? ']' ;
    elements : value (',' value)* ;
  ), benchmark: true)

  class << self
    def parse(text, **opts)
      opts[:symbolize_keys] ||= false
      opts[:debug] ||= false
      root = Grammar.parse(text, debug: opts[:debug])
      root.graphviz.output(png: opts[:output_graphviz]) unless opts[:output_graphviz].to_s.empty?
      root.pretty_print if opts[:print_tree]
      parse_value(root[:value], opts)
    end

    private

    def parse_string(node)
      node.value.undump
    end

    def parse_number(node)
      node.value.to_i == node.value.to_f ? node.value.to_i : node.value.to_f
    end

    def parse_value(node, opts)
      node = node[0]

      case node.name
      when :object then parse_object(node, opts)
      when :array then parse_array(node, opts)
      when :STRING then parse_string(node)
      when :NUMBER then parse_number(node)
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
  end
end

TEST_JSON = %(
  {"widget": {
      "debug": true,
      "window": {
          "title": "Sample K\\u00f6nfabulator Widget",
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

pp Json.parse(TEST_JSON, symbolize_keys: true, output_graphviz: "json.png")
