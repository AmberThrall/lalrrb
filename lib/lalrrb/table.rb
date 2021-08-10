# frozen_string_literal: true

module Lalrrb
  class Table
    def initialize(headings: [])
      @cells = []
      @headings = [] #headings.map(&:to_s)
      @labels = []
    end

    def nrows
      @cells.length
    end

    def ncols
      @headings.length
    end

    def row(index)
      if (f = @labels.find_index(index)).nil?
        @cells[index]
      else
        @cells[f]
      end
    end

    def column(index)
      if (f = @headings.find_index(index)).nil?
        @cells.map { |r| r[index] }
      else
        @cells.map { |r| r[f] }
      end
    end

    def add_row(row = [], label: nil)
      insert_row(nrows, row, label: label)
    end

    def insert_row(index, row = [], label: nil)
      case row
      when Hash then insert_row_hash(index, row, label)
      else insert_row_array(index, row.to_a, label)
      end
    end

    def to_s(uniform_widths: true)
      square_table_off
      return "" if nrows.zero? || ncols.zero?

      col_sizes = []
      ncols.times { |i| col_sizes << (@cells.map { |r| r[i].to_s.length } << @headings[i].to_s.length).max }
      label_size = @labels.map(&:length).max
      col_sizes = [col_sizes.max] * ncols if uniform_widths

      # Print the heading
      s = "┌#{'─' * label_size}"
      col_sizes.each { |size| s += "┬#{'─' * size}" }
      s += "┐\n"
      s += "│#{' ' * label_size}"
      @headings.each_with_index { |h, i| s += "│#{h.rjust(col_sizes[i])}" }
      s += "│\n"
      s += "├#{'─' * label_size}"
      col_sizes.each { |size| s += "┼#{'─' * size}" }
      s += "┤\n"

      # Print the rows
      @cells.each_with_index do |row, index|
        s += "│#{@labels[index].ljust(label_size)}"
        row.each_with_index { |v, i| s += "│#{v.to_s.rjust(col_sizes[i])}" }
        s += "│\n"

        if index < nrows - 1
          s += "├#{'─' * label_size}"
          col_sizes.each { |size| s += "┼#{'─' * size}" }
          s += "┤\n"
        else
          s += "└#{'─' * label_size}"
          col_sizes.each { |size| s += "┴#{'─' * size}" }
          s += "┘\n"
        end
      end

      s
    end

    private

    def insert_row_hash(index, row, label)
      arr = [nil] * ncols
      row.each do |key, value|
        f = @headings.find_index(key.to_s)
        if f.nil?
          @headings << key.to_s
          arr << value
        else
          arr[f] = value
        end
      end
      insert_row_array(index, arr, label)
    end

    def insert_row_array(index, row, label)
      label ||= (nrows + 1).to_s
      @labels.insert(index, label)
      @cells.insert(index, row)
      square_table_off
    end

    def square_table_off
      @cells = @cells.map do |row|
        row.concat([nil] * (ncols - row.length))
      end
      (ncols - @headings.length).times { |_| @headings << (@headings.length + 1).to_s }
    end
  end
end
