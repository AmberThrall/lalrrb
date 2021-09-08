# frozen_string_literal: true

require 'lalrrb'

module CSV
  Lalrrb.create(:Parser, %(
    %token(TEXT, %r/[^",\\n\\r]+/)
    %token(STRING, %r/"(""|[^"])*"/)
    %token(LN, "\\r\\n" / "\\n")
    %start(csv)

    csv = hdr 1*row
    hdr = row
    row = field *("," field) LN
    field = [TEXT / STRING]
), benchmark: true)

  class << self
    def parse(text)
      root = CSV::Parser.parse(text)

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

CSV::Parser::Grammar.syntax_diagram.save("csv-syntax-diagram.svg")

table = CSV.parse(%(Year,Make,Model,Description,Price
1997,Ford,E350,"ac, abs, moon",3000.00
1999,Chevy,"Venture ""Extended Edition""","",4900.00
1999,Chevy,"Venture ""Extended Edition, Very Large""",,5000.00
1996,Jeep,Grand Cherokee,"MUST SELL!
air, moon roof, loaded",4799.00
))
table.pretty_print
