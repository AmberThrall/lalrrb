# frozen_string_literal: true

class Table
  def initialize(data = nil, **options)
    @table = {}
    @options = options
    @row_labels = []
    @groups = {}

    case data
    when nil then nil
    when Table then set(data.columns, data.rows, data)
    when Hash then data.each { |k,v| add_column(k, v) }
    else raise StandardError, "Couldn't handle table data of class #{data.class}"
    end
  end

  def nrows
    @row_labels.length
  end

  def ncols
    @table.keys.length
  end

  def size
    [ncols, nrows]
  end

  def columns
    cols = []
    @groups.each { |_,v| cols.concat v }
    cols.concat ungrouped
    cols
  end

  def column?(column)
    @table.keys.include?(column)
  end

  def rows
    @row_labels
  end

  def row?(row)
    @row_labels.include?(row)
  end

  def groups
    @groups.keys
  end

  def group(name)
    @groups[name].to_a
  end

  def group_add(name, *columns)
    columns = Array(columns).flatten.map { |c| c.is_a?(Range) ? c.to_a : c }.flatten

    @groups[name] ||= []
    columns.each do |col|
      col = @table.keys[col] if col.is_a?(Integer)
      next unless column?(col)

      @groups.each { |g,v| raise StandardError, "Column '#{col}' is already in group '#{g}'." if v.include?(col) }

      @groups[name] << col
    end
  end

  def group_remove(*columns)
    columns = Array(columns).flatten.map { |c| c.is_a?(Range) ? c.to_a : c }.flatten

    columns.each do |col|
      col = @table.keys[col] if col.is_a?(Integer)
      @groups.each { |g,v| v.delete(col) }
    end
  end

  def [](column, row)
    get(column, row)
  end

  def []=(column, row, value)
    set(column, row, value)
  end

  def get(column, row)
    columns = Array(column).flatten.map do |col|
      case col
      when Integer then self.columns[col]
      when String, Symbol then col
      when Range
        case col.min
        when Integer then self.columns[col]
        when String, Symbol then col.to_a
        end
      end
    end.flatten
    columns.delete_if { |c| !column?(c) }
    return nil if columns.empty?

    rows = Array(row).flatten.map do |r|
      case r
      when Integer then r
      when String, Symbol then @row_labels.find_index(r)
      when Range
        case r.min
        when Integer then r.to_a
        when String, Symbol then r.map { |r2| @row_labels.find_index(r2) }
        end
      end
    end.flatten
    rows.delete(nil)
    return nil if rows.empty?

    return @table[columns.first][:data][rows.first] if columns.length == 1 && rows.length == 1

    ret = Table.new
    columns.each { |c| ret.add_column(c) }
    rows.each do |r|
      ret.add_row() if @row_labels.is_a?(Integer)
      ret.add_row(label: @row_labels[r]) unless @row_labels.is_a?(Integer)
      row = @row_labels.is_a?(Integer) ? ret.nrows - 1 : @row_labels[r]
      columns.each { |c| ret[c,row] = get(c, r) }
    end
    ret
  end

  def set(column, row, value)
    columns = Array(column).flatten.map do |col|
      case col
      when Integer then self.columns[col]
      when String, Symbol then col
      when Range
        case col.min
        when Integer then self.columns[col]
        when String, Symbol then col.to_a
        end
      end
    end.flatten
    columns.delete(nil)
    columns.filter { |c| !column?(c) }.each { |c| add_column(c) }

    rows = Array(row).flatten.map do |r|
      case r
      when Integer then r
      when String, Symbol
         f = @row_labels.find_index(r)
         add_row(label: r) if f.nil?
         f.nil? ? nrows - 1 : f
      when Range
        case r.min
        when Integer then r.to_a
        when String, Symbol
          r.map do |r2|
            f = @row_labels.find_index(r2)
            add_row(label: r2) if f.nil?
            f.nil? ? nrows - 1 : f
          end
        end
      end
    end.flatten
    rows.delete(nil)
    rows.each { |r| add_row while r >= nrows }

    return @table[columns.first][:data][rows.first] = value if columns.length == 1 && rows.length == 1

    columns.each_with_index do |c, i|
      rows.each_with_index do |r, j|
        @table[c][:data][r] = value.is_a?(Table) ? value[c,j] : value
      end
    end

    self
  end

  def save(filename, delim: ',')
    f = File.open(filename, 'w')

    # Header
    f.print "\"#{@options[:index_label].to_s.gsub('"', '""')}\"#{ncols > 0 ? delim : ''}" unless @options[:index_label].to_s.empty?
    @table.keys.each { |c| f.print "#{c == @table.keys.first ? '' : delim}\"#{c.to_s.gsub('"', '""')}\"" }
    f.puts ""

    # Data
    nrows.times do |row|
      f.print "\"#{@row_labels[row].to_s.gsub('"', '""')}\"#{delim}" unless @options[:index_label].to_s.empty?
      @table.keys.each { |c| f.print "#{c == @table.keys.first ? '' : delim}\"#{get(c,row).to_s.gsub('"', '""')}\"" }
      f.puts ""
    end

    f.close
  end

  def self.csv(arg, **options)
    delim = options[:delim]
    options.delete(:delim)
    delim ||= ','
    decimal = options[:decimal_sep]
    options.delete(:decimal_sep)
    decimal_sep ||= '.'
    symbolize_headings = options[:symbolize_headings]
    options.delete(:symbolize_headings)
    symbolize_headings ||= false

    regex = Regexp.new "(?:[^\"\\#{delim}\\r\\n]*(?:\"(?:(?:\"\")?[^\"]*)*\")?)*(?:\\#{delim}|\\r?\\n|\\z)" # magic
    table = Table.new(options)

    arg = File.read(arg) if File.exist?(arg)
    rows = []
    current_row = []
    loop do
      c = arg.match(regex).to_s
      break if c.empty? || arg[..c.length - 1] != c

      arg = arg[c.length..]
      last = c[-1]
      c = c.chomp
      c = c[..-1 - delim.length] if last == delim
      c = c[1..-2].gsub('""', '"') if c[0] == '"' && c[-1] == '"'
      c = parse_cell(c, decimal_sep: decimal_sep) if rows.length.positive?

      current_row << c
      if last == "\n"
        rows << current_row
        current_row = []
      end
    end
    rows << current_row unless current_row.empty?
    return table if rows.empty?

    rows.first.each { |c| table.add_column(symbolize_headings ? c.to_sym : c) }
    rows[1..].each do |row|
      table.add_row
      row.each_with_index { |c,i| table[table.columns[i], table.nrows - 1] = c }
    end

    table
  end

  def pretty_print(unicode: true)
    return if ncols == 0

    string_table = Table.new
    @table.each do |k,v|
      v[:data].each_with_index { |c,i| string_table[k,i] = c.to_s }
    end

    index_width = [@options[:index_label].to_s.length, @row_labels.map { |l| l.to_s.length }].flatten.max
    col_widths = {}
    @table.keys.each do |k|
      col_widths[k] = [k.to_s.length, [*(0..nrows-1)].map { |i| string_table[k,i].lines.map(&:length).max.to_i }].flatten.max
      col_widths[k] = @table[k][:width] unless @table[k][:width].nil?
    end
    group_width = {}
    @groups.each { |g,v| group_width[g] = v.map { |c| col_widths[c] + 1 }.sum - 1 }
    @groups.each { |g,v| next if v&.empty?; col_widths[v.last] += [g.to_s.length - group_width[g], 0].max }
    @groups.keys.each { |g| group_width[g] = g.to_s.length if group_width[g] < g.to_s.length }

    row_height = []
    nrows.times do |i|
      row_height << [1, @table.keys.map { |k| string_table[k,i].lines.length }.max].max
    end

    # Print the header
    first = true
    unless @options[:index_label].to_s.empty?
      print unicode ? '┏' : '+'
      print (unicode ? '━' : '-') * index_width
      first = false
    end

    if @groups.empty?
      col_widths.each { |_,x| print(unicode ? first ? '┏' : '┳' : '+'); print (unicode ? '━' : '-') * x; first = false }
      puts unicode ? '┓' : '+'

      print "#{unicode ? '┃' : '|'}#{cjust(@options[:index_label], index_width)}" unless @options[:index_label].to_s.empty?
      @table.keys.each { |k| print "#{unicode ? '┃' : '|'}#{cjust(k, col_widths[k])}" }
      puts unicode ? '┃' : '|'
    else
      @groups.keys.each { |g| print(unicode ? first ? '┏' : '┳' : '+'); print (unicode ? '━' : '-') * group_width[g]; first = false }
      ungrouped.each { |c| print(unicode ? first ? '┏' : '┳' : '+'); print (unicode ? '━' : '-') * col_widths[c]; first = false }
      puts unicode ? '┓' : '+'

      print "#{unicode ? '┃' : '|'}#{' ' * index_width}" unless @options[:index_label].to_s.empty?
      @groups.keys.each { |g| print "#{unicode ? '┃' : '|'}#{cjust(g.to_s, group_width[g])}"}
      ungrouped.each { |c| print "#{unicode ? '┃' : '|'}#{' ' * col_widths[c]}" }
      puts unicode ? '┃' : '|'

      print "#{unicode ? '┃' : '|'}#{cjust(@options[:index_label], index_width)}" unless @options[:index_label].to_s.empty?
      very_first = true
      @groups.each do |g,v|
        first = true;
        v.each { |c| print "#{unicode ? first ? very_first ? '┣' : '╋' : '┳' : '+'}#{(unicode ? '━' : '-') * col_widths[c]}"; first = false }
        very_first = false
      end
      ungrouped.each { |c| print "#{ungrouped.first == c ? unicode ? '┫' : '+' : unicode ? '┃' : '|'}#{cjust(c.to_s,col_widths[c])}" }
      puts ungrouped.length.positive? ? unicode ? '┃' : '|' : unicode ? '┫' : '+'

      print "#{unicode ? '┃' : '|'}#{' ' * index_width}" unless @options[:index_label].to_s.empty?
      @groups.each { |g,v| v.each { |c| print "#{unicode ? '┃' : '|'}#{cjust(c.to_s, col_widths[c])}" } }
      ungrouped.each { |c| print "#{unicode ? '┃' : '|'}#{' ' * col_widths[c]}" }
      puts unicode ? '┃' : '|'
    end

    if nrows == 0
      first = true
      unless @options[:index_label].to_s.empty?
        print unicode ? '└' : '+'
        print (unicode ? '─' : '-') * index_width
        first = false
      end

      @groups.each { |g,v| first = true; v.each { |c| print "#{unicode ? first ? '└' : '┴' : '+'}#{(unicode ? '─' : '-') * col_widths[c]}";  first = false;} }
      ungrouped.each { |c| print "#{unicode ? first ? '└' : '┴' : '+'}#{(unicode ? '─' : '-') * col_widths[c]}";  first = false; }
      puts unicode ? '┘' : '+'
    else
      first = true
      unless @options[:index_label].to_s.empty?
        print unicode ? '┡' : '+'
        print (unicode ? '━' : '-') * index_width
        first = false
      end

      @groups.each { |g,v| v.each { |c| print "#{unicode ? first ? '┡' : '╇' : '+'}#{(unicode ? '━' : '-') * col_widths[c]}";  first = false; } }
      ungrouped.each { |c| print "#{unicode ? first ? '┡' : '╇' : '+'}#{(unicode ? '━' : '-') * col_widths[c]}";  first = false; }
      puts unicode ? '┩' : '+'
    end

    # Print the cells
    nrows.times do |row|
      index = format_cell(@row_labels[row].to_s, index_width, row_height[row], :center, :center)
      @table.keys.each do |k|
        string_table[k, row] = format_cell(string_table[k, row], col_widths[k], row_height[row], @table[k][:align], @table[k][:valign])
      end

      row_height[row].times do |lineno|
        print "#{unicode ? '│' : '|'}#{index[lineno]}" unless @options[:index_label].to_s.empty?
        @groups.each { |_,v| v.each { |k| print unicode ? '│' : '|'; print string_table[k,row][lineno] } }
        ungrouped.each { |k| print unicode ? '│' : '|'; print string_table[k,row][lineno] }
        puts unicode ? '│' : '|'
      end

      if row < nrows - 1
        first = true
        unless @options[:index_label].to_s.empty?
          print unicode ? '├' : '+'
          print (unicode ? '─' : '-') * index_width
          first = false
        end
        @groups.each { |g,v| v.each { |c| print(unicode ? first ? '├' : '┼' : '+'); print (unicode ? '─' : '-') * col_widths[c]; first = false } }
        ungrouped.each { |c| print(unicode ? first ? '├' : '┼' : '+'); print (unicode ? '─' : '-') * col_widths[c]; first = false }
        puts unicode ? '┤' : '+'
      else
        first = true
        unless @options[:index_label].to_s.empty?
          print unicode ? '└' : '+'
          print (unicode ? '─' : '-') * index_width
          first = false
        end
        @groups.each { |g,v| v.each { |c| print(unicode ? first ? '└' : '┴' : '+'); print (unicode ? '─' : '-') * col_widths[c]; first = false } }
        ungrouped.each { |c| print(unicode ? first ? '└' : '┴' : '+'); print (unicode ? '─' : '-') * col_widths[c]; first = false }
        puts unicode ? '┘' : '+'
      end
    end
  end

  def to_h
    hash = {}
    @table.keys.each do |k|
      data = {}
      @row_labels.each { |i| data[i] = get(k, i) }
      hash[k] = data
    end
    hash
  end

  def rename_row(row, label = nil)
    raise StandardError, "Row '#{row}' already exists" if row?(label)

    row = @row_labels.find_index(row) unless row.is_a?(Integer)
    label ||= row

    @row_labels[row] = label unless @row_labels[row].nil?
    correct_indices
    self
  end

  def add_row(label = nil, **data)
    insert_row(nrows, label, **data)
  end

  def insert_row(row, label = nil, **data)
    raise StandardError, "Row '#{row}' already exists" if row?(label)

    row = @row_labels.find_index(row) unless row.is_a?(Integer)
    row ||= nrows
    label ||= row

    @table.each { |k,v| v[:data].insert(row, nil) }
    @row_labels.insert(row, label)
    correct_indices

    data.each { |k,v| set(k, row, v) }
    self
  end

  def add_column(heading, data = nil, options = {})
    raise StandardError, "Column '#{heading}' already exists" if column?(heading)
    options[:align] ||= :center
    options[:valign] ||= :top

    case data
    when Hash then add_column_from_hash(heading, data, options)
    else add_column_from_array(heading, Array(data), options)
    end

    self
  end

  def remove_column(heading)
    heading = columns[heading] if heading.is_a?(Integer)
    return unless column?(heading)

    group_remove(heading)
    @table.delete(heading)
    self
  end

  def remove_row(row)
    row = @row_labels.find_index(row) unless row.is_a?(Integer)
    return if @row_labels[row].nil?

    @row_labels.delete_at(row)
    @table.each { |k,v| v.delete_at(row) }
    correct_indices
    self
  end

  private

  def ungrouped
    list = @table.keys
    @groups.each { |g,v| v.each { |h| list.delete(h) } }
    list
  end

  def self.parse_cell(cell, decimal_sep: '.')
    return nil if cell.empty?
    return true if cell.strip == 'true'
    return false if cell.strip == 'false'
    return cell.to_i if cell.strip.match(/[0-9]+/).to_s == cell
    return cell.gsub(decimal_sep, '.').to_f if cell.strip.match(Regexp.new "[0-9]+\\#{decimal_sep}[0-9]+").to_s == cell
    cell
  end

  def add_column_from_hash(heading, data, options)
    arr = [nil] * nrows
    data.each do |k,v|
      if f = @row_labels.find_index(k)
        arr[f] = v
      else
        add_row(label: k)
        arr << v
      end
    end
    add_column_from_array(heading, arr, options)
  end

  def add_column_from_array(heading, data, options)
    @table[heading] = options
    @table[heading][:data] = data
    square_off_table
  end

  def square_off_table
    @table.each do |k,v|
      @row_labels << nrows while nrows < v[:data].length
    end

    @table.each do |k,v|
      v[:data].concat ([nil] * (nrows - v[:data].length)) if v[:data].length < nrows
    end
  end

  def correct_indices
    @row_labels.each_with_index { |x,i| @row_labels[i] = i if x.is_a?(Integer) }
  end

  def cjust(text, width)
    offset = width / 2 - text.to_s.length / 2
    s = ' ' * [offset.to_i, 0].max
    s += text.to_s
    s += ' ' * [width - offset.to_i - text.length, 0].max
    s
  end

  def format_cell(cell, width, height, align, valign)
    lines = cell.to_s.lines
    case valign
    when :center
      offset = [height / 2 - lines.length / 2, 0].max
      lines = [[""] * offset.to_i, lines, [""] * [height - offset.to_i - lines.length, 0].max].flatten
    when :bottom then lines = [[""] * [0, height - lines.length].max, lines].flatten
    else lines.concat ([""] * [height - lines.length, 0].max)
    end
    lines = lines[..height]

    lines.map do |line|
      case align
      when :left then line[..width].chomp.ljust(width)
      when :right then line[..width].chomp.rjust(width)
      else cjust(line[..width].chomp, width)
      end
    end
  end
end
