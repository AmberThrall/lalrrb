# frozen_string_literal: true

module Lalrrb
  class Table
    attr_reader :cells

    def initialize(headings = [])
      @cells = []
      @headings = headings
      @row_labels = []
      @modified = false
    end

    def nrows
      @cells.length
    end

    def ncols
      @headings.length
    end

    def modified?(clear_flag: true)
      m = @modified
      clear_modified if clear_flag
      m
    end

    def clear_modified
      @modified = false
    end

    def rows(*indices)
      table = Table.new(@headings)
      return table if nrows.zero? || ncols.zero?

      indices.each do |index|
        min, max = case index
                   when Integer then [index] * 2
                   when String, Symbol then [@row_labels.find_index(index)] * 2
                   when Range then [index.min, index.max]
                   else raise Error, "Invalid argument '#{index}'."
                   end

          return nil if min.nil? || max.nil?

          (min..max).each { |x| table.add_row(@cells[x].clone, label: @row_labels[x]) }
        end

        table
    end

    def columns(*indices)
      table = Table.new
      return table if nrows.zero? || ncols.zero?

      indices.each do |index|
        min, max = case index
                   when Integer then [index] * 2
                   when String, Symbol then [@headings.find_index(index)] * 2
                   when Range then [index.min, index.max]
                   else raise Error, "Invalid argument '#{index}'."
                   end

        return nil if min.nil? || max.nil?

        (min..max).each { |x| table.add_column(@cells.map { |r| r[x].clone }, heading: @headings[x]) }
      end

      table
    end

    def [](col, row)
      get(col, row)
    end

    def []=(col, row, value)
      set(col, row, value)
    end

    def get(column, row)
      subtable = rows(row).columns(column)
      return subtable if subtable.nrows > 1 || subtable.ncols > 1

      subtable.cells[0][0]
    end

    def set(column, row, value)
      x1, x2 = case column
               when Integer then [column] * 2
               when String, Symbol then [@headings.find_index(column)] * 2
               when Range then [column.min, column.max]
               else raise Error, "Invalid argument '#{column}'."
               end

      y1, y2 = case row
               when Integer then [row] * 2
               when String, Symbol then [@row_labels.find_index(row)] * 2
               when Range then [row.min, row.max]
               else raise Error, "Invalid argument '#{row}'."
               end

      raise Error, "Out of bounds (#{column},#{row})" if x1.nil? || x2.nil? || y1.nil? || y2.nil?

      if x1 == x2 && y1 == y2
        @modified = true unless @cells[y1][x1] == value
        return @cells[y1][x1] = value
      end

      value.nrows.each do |x|
        value.ncols.each do |y|
          @modified = true unless @cells[y1 + y][x1 + x] == value[y][x]
          @cells[y1 + y][x1 + x] = value[y][x]
        end
      end
    end

    def add_row(row = [], label: nil)
      insert_row(nrows, row, label: label)
    end

    def insert_row(index, row = [], label: nil)
      index = [index, nrows].min
      case row
      when Hash then insert_row_hash(index, row, label)
      else insert_row_array(index, row.to_a, label)
      end
    end

    def add_column(col = [], heading: nil)
      insert_column(ncols, col, heading: heading)
    end

    def insert_column(index, col = [], heading: nil)
      index = [index, ncols].min
      case col
      when Hash then insert_column_hash(index, col, heading)
      else insert_column_array(index, col.to_a, heading)
      end
    end

    def to_s(uniform_widths: true)
      square_table_off
      return "" if nrows.zero? || ncols.zero?

      col_sizes = []
      ncols.times { |i| col_sizes << (@cells.map { |r| r[i].to_s.length } << @headings[i].to_s.length).max }
      label_size = @row_labels.map(&:length).max
      col_sizes = [col_sizes.max] * ncols if uniform_widths

      # Print the heading
      s = "┌#{'─' * label_size}"
      col_sizes.each { |size| s += "┬#{'─' * size}" }
      s += "┐\n"
      s += "│#{' ' * label_size}"
      @headings.each_with_index { |h, i| s += "│#{h.to_s.rjust(col_sizes[i])}" }
      s += "│\n"
      s += "├#{'─' * label_size}"
      col_sizes.each { |size| s += "┼#{'─' * size}" }
      s += "┤\n"

      # Print the rows
      @cells.each_with_index do |row, index|
        s += "│#{@row_labels[index].to_s.ljust(label_size)}"
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

    def save(file, delim: ',')
      f = File.open(file, 'w')
      f.puts "#{delim}#{@headings.map { |h| "\"#{h.to_s.gsub('"', '""')}\"" }.join(delim)}"
      @cells.each_with_index do |row, index|
        f.puts "\"#{@row_labels[index].to_s.gsub('"', '""')}\"#{delim}#{row.map { |c| "\"#{c.to_s.gsub('"', '""')}\""}.join(delim)}"
      end
      f.close
    end

    private

    def insert_row_hash(index, row, label)
      arr = [nil] * ncols
      row.each do |key, value|
        f = @headings.find_index(key)
        if f.nil?
          @headings.insert(index, key)
          arr.insert(index, value)
        else
          arr[f] = value
        end
      end
      insert_row_array(index, arr, label)
    end

    def insert_row_array(index, row, label)
      label ||= nrows.to_s
      @row_labels.insert(index, label)
      @cells.insert(index, row)
      @modified = true
      square_table_off
    end

    def insert_column_hash(index, col, heading)
      arr = [nil] * nrows
      col.each do |key, value|
        f = @headings.find_index(key)
        if f.nil?
          @headings.insert(index, key)
          arr.insert(index, value)
        else
          arr[f] = value
        end
      end

      insert_column_array(index, arr, heading)
    end

    def insert_column_array(index, col, heading)
      heading ||= ncols.to_s
      (col.length - nrows).times { add_row([nil] * ncols) }
      @headings.insert(index, heading)
      col.each_with_index { |v, i| @cells[i].insert(index, v) }
      @modified = true
      square_table_off
    end

    def square_table_off
      @cells = @cells.map do |row|
        row.concat([nil] * [ncols - row.length, 0].max)
      end
      (ncols - @headings.length).times { |_| @headings << (@headings.length + 1).to_s }
    end
  end
end
