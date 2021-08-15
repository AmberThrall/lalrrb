# frozen_string_literal: true

module Lalrrb
  class Table
    attr_reader :cells
    attr_accessor :index_label

    def initialize(headings = [], index_label: '')
      @cells = []
      @headings = headings
      @row_labels = []
      @groups = {}
      @modified = false
      @index_label = index_label
    end

    def nrows
      @cells.length
    end

    def ncols
      @headings.length
    end

    def add_group(groupname, *indices)
      new_group = []
      Array(indices).flatten.each do |index|
        min, max = case index
                   when Integer then [index] * 2
                   when String, Symbol then [@headings.find_index(index)] * 2
                   when Range then [index.min, index.max]
                   else raise Error, "Unsupported argument of class #{index.class}."
                   end

        next if min.nil? || max.nil?

        (min..max).each { |x| new_group << x }
      end

      @groups.each do |k, v|
        next if k == groupname
        raise Error, "New group intersects with group '#{k}'" unless new_group.intersection(v).empty?
      end

      @groups[groupname] ||= []
      @groups[groupname].concat new_group.uniq
    end

    def modified?(clear_flag: true)
      m = @modified
      clear_modified if clear_flag
      m
    end

    def clear_modified
      @modified = false
    end

    def flag_modified
      @modified = true
    end

    def rows(*indices)
      table = Table.new(@headings)
      return table if nrows.zero? || ncols.zero?

      Array(indices).flatten.each do |index|
        min, max = case index
                   when Integer then [index] * 2
                   when String, Symbol then [@row_labels.find_index(index)] * 2
                   when Range then [index.min, index.max]
                   else raise Error, "Unsupported argument of class #{index.class}."
                   end

          return nil if min.nil? || max.nil?

          (min..max).each { |x| table.add_row(@cells[x].clone, label: @row_labels[x]) }
        end

        table
    end

    def columns(*indices)
      table = Table.new
      return table if nrows.zero? || ncols.zero?

      Array(indices).flatten.each do |index|
        min, max = case index
                   when Integer then [index] * 2
                   when String, Symbol then [@headings.find_index(index)] * 2
                   when Range then [index.min, index.max]
                   else raise Error, "Unsupported argument of class #{index.class}."
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
      subtable = rows(row)
      raise Error, "Out of bounds: unknown row '#{row}'" if subtable.nil?

      subtable = subtable.columns(column)
      raise Error, "Out of bounds: unknown column '#{column}'" if subtable.nil?

      return subtable if subtable.nrows > 1 || subtable.ncols > 1

      subtable.cells[0][0]
    end

    def set(column, row, value)
      x1, x2 = case column
               when Integer then [column] * 2
               when String, Symbol then [@headings.find_index(column)] * 2
               when Range then [column.min, column.max]
               else raise Error, "Unsupported argument of class #{column.class}."
               end

      y1, y2 = case row
               when Integer then [row] * 2
               when String, Symbol then [@row_labels.find_index(row)] * 2
               when Range then [row.min, row.max]
               else raise Error, "Unsupported argument of class #{row.class}."
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
      label_size = [index_label.length, @row_labels.map(&:length)].flatten.max
      col_sizes = [col_sizes.max] * ncols if uniform_widths
      group_width = {}
      @groups.each do |k,v|
        group_width[k] = v.map { |i| col_sizes[i] + 1 }.sum - 1
      end

      # Print the heading
      unless @groups.empty?
        s = "┌#{'─' * label_size}"
        @groups.each { |k,v| s += "┬#{'─' * group_width[k]}" }
        ungrouped.each { |i| s += "┬#{'─' * col_sizes[i]}" }
        s += "┐\n"

        s += "│#{' ' * label_size}"
        @groups.each { |k,v| s += "│#{cjust(k, group_width[k])}" }
        ungrouped.each { |i| s += "│#{' ' * col_sizes[i]}" }
        s += "│\n"

        label_offset = label_size / 2 - @index_label.to_s.length / 2
        s += "│#{cjust(index_label, label_size)}"
        first_group = true
        @groups.each { |k,v| v.each { |i| s += "#{i == v.first ? first_group ? '├' : '┼' : '┬'}#{'─' * col_sizes[i]}" }; first_group = false }
        s += ungrouped.empty? ? '│' : '┤'
        ungrouped.each { |i| s += "#{cjust(@headings[i], col_sizes[i])}│" }
        s += "\n"

        s += "│#{' ' * label_size}"
        @groups.each { |k,v| v.each { |i| s += "│#{cjust(@headings[i], col_sizes[i])}" } }
        ungrouped.each { |i| s += "│#{' ' * col_sizes[i]}" }
        s += "│\n"
        s += "#{nrows.zero? ? '└' : '├'}#{'─' * label_size}"
        col_sizes.each { |size| s += "#{nrows.zero? ? '┴' : '┼'}#{'─' * size}" }
        s += nrows.zero? ? "┘\n" : "┤\n"
      else
        s = "┌#{'─' * label_size}"
        col_sizes.each { |size| s += "┬#{'─' * size}" }
        s += "┐\n"

        s += "│#{cjust(@index_label, label_size)}"
        ungrouped.each { |i| s += "│#{cjust(@headings[i], col_sizes[i])}" }
        s += "│\n"

        s += "#{nrows.zero? ? '└' : '├'}#{'─' * label_size}"
        col_sizes.each { |size| s += "#{nrows.zero? ? '─' : '┼'}#{'─' * size}" }
        s += nrows.zero? ? "┘\n" : "┤\n"
      end

      # Print the rows
      @cells.each_with_index do |row, index|
        s += "│#{cjust(@row_labels[index], label_size)}"
        @groups.each { |k,v| v.each { |i| s += "│#{cjust(row[i], col_sizes[i])}" } }
        ungrouped.each { |i| s += "│#{cjust(row[i], col_sizes[i])}" }
        s += "│\n"

        s += "#{index < nrows - 1 ? '├' : '└'}#{'─' * label_size}"
        @groups.each { |k,v| v.each { |i| s += "#{index < nrows - 1 ? '┼' : '┴'}#{'─' * col_sizes[i]}" } }
        ungrouped.each { |i| s += "#{index < nrows - 1 ? '┼' : '┴'}#{'─' * col_sizes[i]}" }
        s += "#{index < nrows - 1 ? '┤' : '┘'}\n"
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

    def ungrouped
      list = [*(0..ncols - 1)]
      @groups.each { |k,v| list.delete_if { |x| v.include? x } }
      list
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

    def cjust(string, width)
      offset = width / 2 - string.to_s.length / 2
      "#{' ' * offset.to_i}#{string}#{' ' * (width - offset.to_i - string.to_s.length)}"
    end
  end
end
