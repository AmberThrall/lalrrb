# frozen_string_literal: true

module Lalrrb
  TextPosition = Struct.new(:offset, :text) do
    def line
      text[..offset].count("\n") + 1
    end

    def column
      offset - text[..offset].rindex("\n").to_i + 1
    end

    def to_i
      offset
    end

    def to_s
      "#{line}:#{column}"
    end
  end

  class Token
    attr_accessor :name, :value, :position

    def initialize(name, value, position)
      @name = name
      @value = value
      @position = position
    end

    def to_s
      @name.to_s
    end

    def ==(other)
      case other
      when Token then @name == other.name && @value == other.value && @position == other.position
      when String then @value == other
      when Symbol then @name == other
      else false
      end
    end
  end

  class LexerError < StandardError
    def initialize(position, text, mode, text_preview_length: 10)
      pos = TextPosition.new(position, text)
      text_preview = text[position..].dump[1..-2]
      text_preview = "#{text_preview[..text_preview_length]}..." if text_preview.length > text_preview_length
      super "#{pos}: Couldn't match any tokens with string \"#{text_preview}\"#{mode == :default ? '' : " in mode `#{mode}'"}."
    end
  end

  class Lexer
    attr_reader :tokens, :conflict_mode

    CONFLICT_MODES = [:longest, :first]

    def initialize
      @tokens = {}
      @conflict_mode = CONFLICT_MODES.first
    end

    def token(name, match, skip: false, more: false, insensitive: false, mode: :default, &block)
      raise Error, "EOF is a reserved token name" if name == :EOF
      raise Error, "token name `#{name}' is taken" if @tokens.include?(name)
      raise Error, "cannot declare token with empty match" if match.to_s.empty?

      match = Array(match).map { |m| m.is_a?(Regexp) ? Regexp.new(m.source, Regexp::IGNORECASE) : m } if insensitive

      block_closure = block.nil? ? nil : proc { |x| instance_exec(x, &block) }
      @tokens[name] = { match: match, skip: skip, more: more, insensitive: insensitive, mode: mode, block: block_closure }
    end

    def delete_token(name)
      @tokens.delete(name)
    end

    def conflict_mode=(method)
      method = method.to_s.downcase.to_sym
      raise Error, "invalid conflict mode `#{method}'. Options: #{CONFLICT_MODES.join(', ')}" unless CONFLICT_MODES.include?(method)

      @conflict_mode = method
    end

    def tokenize(text, debug: false)
      @text = text
      @position = 0
      @mode = [:default]

      tokens = []
      more = nil
      if debug
        puts "line \# column length match"
        puts "====== ====== ====== ====================="
      end

      while @position < @text.length
        matches = get_matches(@position)
        raise LexerError.new(@position, @text, @mode.last) if matches.empty?

        matches = matches.sort { |a,b| b.value.length <=> a.value.length } if @conflict_mode == :longest
        t = matches.first

        if debug
          pos = TextPosition.new(@position, @text)
          print pos.line.to_s.ljust(6)
          print " "
          print pos.column.to_s.ljust(6)
          print " "
          print t.value.length.to_s.ljust(6)
          print " "
          puts "#{t.name} : \"#{t.value.dump[1..-2]}\""
        end

        @position = t.position.offset + t.value.length

        t.value = "" if @tokens[t.name][:skip]
        t.value = "#{more}#{t.value}"
        unless @tokens[t.name][:block].nil?
          new_value = @tokens[t.name][:block].call(t.value)
          t.value = new_value unless new_value.nil?
        end
        more = @tokens[t.name][:more] ? t.value.to_s : nil

        tokens << t unless (@tokens[t.name][:skip] && t.value.to_s.empty?) || @tokens[t.name][:more]
      end

      tokens << Token.new(:EOF, :EOF, TextPosition.new(@text.length, @text))
      tokens
    end

    private

    def push_mode(mode)
      @mode << mode
      nil
    end

    def pop_mode
      return nil if @mode.length == 1

      @mode.pop
      nil
    end

    def mode(mode)
      @mode[-1] = mode
      nil
    end

    def get_matches(pos)
      matches = []
      @tokens.each do |name, data|
        next unless data[:mode] == @mode.last

        s = nil
        Array(data[:match]).each do |m|
          m = @text[pos..].match(m) if m.is_a?(Regexp)
          next if m.to_s.empty?

          if (data[:insensitive] && @text[pos..pos + m.to_s.length - 1].downcase == m.to_s.downcase) ||
              (!data[:insensitive] && @text[pos..pos + m.to_s.length - 1] == m.to_s)
            s = @text[pos..pos + m.to_s.length - 1]
            break
          end
        end

        matches << Token.new(name, s, TextPosition.new(pos, @text)) unless s.nil?
      end

      matches
    end
  end
end
