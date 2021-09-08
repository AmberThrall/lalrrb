# frozen_string_literal: true

module Lalrrb
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

  class Lexer
    attr_reader :tokens

    def initialize
      @tokens = {}
    end

    def token(name, match, *flags, &block)
      return if match.to_s.empty? || @tokens.include?(name)

      block_closure = block.nil? ? nil : proc { |x| instance_exec(x, &block) }
      @tokens[name] = { match: match, flags: convert_flags(name, flags), block: block_closure }
    end

    def ignore(match, *flags)
      return if match.to_s.empty?

      i = 0
      name = "ignore#{i += 1}".to_sym while name.nil? || @tokens.include?(name)

      flags = convert_flags(name, flags)
      flags[:ignore] = true
      @tokens[name] = { match: match, flags: flags, block: nil }
    end

    def delete_token(name)
      @tokens.delete(name)
    end

    def start(text)
      @text = text
      @position = 0
    end

    def lineno
      @text[..@position].count("\n") + 1
    end

    def next
      matches = get_matches(@position)
      raise StandardError, "Couldn't match any tokens with string '#{@text[@position..].length > 10 ? @text[@position..@position+10] + '...' : @text[@position..]}'" if matches.empty?

      matches.sort { |a,b| b.value.length <=> a.value.length }
    end

    def accept(token)
      @position = token.position + token.value.length
      token.value = @tokens[token.name][:block].call(token.value) unless @tokens[token.name][:block].nil?
    end

    private

    def get_matches(pos)
      return [Token.new(:EOF, :EOF, @text.length)] if pos == @text.length

      matches = @tokens.map do |name, data|
        s = nil
        Array(data[:match]).each do |m|
          m = @text[pos..].match(m) if m.is_a?(Regexp)
          if (data[:flags][:insensitive] && @text[pos..pos + m.to_s.length - 1].downcase == m.to_s.downcase) ||
              (!data[:flags][:insensitive] && @text[pos..pos + m.to_s.length - 1] == m.to_s)
            s = @text[pos..pos + m.to_s.length - 1]
            break
          end
        end

        s.to_s.empty? ? nil : (data[:flags][:ignore] ? get_matches(pos + s.length) : Token.new(name, s, pos))
      end.flatten
      matches.delete(nil)
      matches
    end

    def convert_flags(name, flags)
      _flags = { insensitive: false, ignore: false }

      flags.each do |flag|
        case flag
        when :i, :insensitive then _flags[:insensitive] = true
        when :s, :sensitive then _flags[:insensitive] = false
        when :ignore then _flags[:ignore] = true
        else raise StandardError, "Invalid flag '#{flag}' in token '#{name}'"
        end
      end

      _flags
    end
  end
end
