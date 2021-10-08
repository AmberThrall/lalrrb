# frozen_string_literal: true

require 'lalrrb'
require 'lalrrb/ext'

module CSV
  Parser = Lalrrb.create(%(
    /**
     * A grammar for Comma-separated values (CSV).
     *
     * Modified from: https://github.com/antlr/grammars-v4/blob/848128bbe7e5ae6db901192c5665d877d0fcceff/csv/CSV.g4
     */

    // Tokens
    token TEXT : [^",\\n\\r]+ ;
    token STRING : '"' ('""'|[^"])* '"' ;
    token LN : \\r? \\n ;

    // Entry point for grammar
    options {
      start = csv;
      conflict_mode = first;
    }

    // Actual rule definitions
    csv : hdr row+ ;
    hdr : row ;

    row : field ("," field)* LN ;
    field
      : TEXT
      | STRING
      |
      ;
  ), benchmark: true, benchmark_caption: "", benchmark_format: "%10.6t s\n")

  class << self
    def parse(text, debug: false)
      root = CSV::Parser.parse(text, debug: debug)

      table = Lalrrb::Table.new
      row(root[:hdr][:row]).each { |v| table.add_column(v) }
      Array(root[:row]).each_with_index do |row, i|
        row(row).each_with_index { |v, j| table[j,i] = v }
      end
      table
    end

    private

    def row(node)
      Array(node[:field]).map do |field|
        case field[0]&.name
        when :TEXT then field[0].value
        when :STRING then field[0].value[1..-2].gsub('""', '"')
        else nil
        end
      end
    end
  end
end

puts CSV::Parser::Grammar
CSV::Parser::Grammar.syntax_diagram.save("csv-syntax-diagram.svg")

table = CSV.parse(%(Year,Make,Model,Description,Price
1997,Ford,E350,"ac, abs, moon",3000.00
1999,Chevy,"Venture ""Extended Edition""","",4900.00
1999,Chevy,"Venture ""Extended Edition, Very Large""",,5000.00
1996,Jeep,Grand Cherokee,"MUST SELL!
air, moon roof, loaded",4799.00
), debug: true)
table.pretty_print
