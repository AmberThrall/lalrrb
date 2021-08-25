# frozen_string_literal: true

module Lalrrb
  class Token
    attr_accessor :name, :value

    def initialize(name, value)
      @name = name
      @value = value
    end

    def to_s
      "#{@name}"
    end

    def ==(other)
      case other
      when Token then @name == other.name && @value == other.value
      when String then @value == other
      when Symbol then @name == other
      else false
      end
    end
  end

  class Lexer
    def initialize
      @tokens = {}
      @state = nil
    end

    def tokens
      @tokens.keys
    end

    def token(name, match, state: nil, &block)
      return if match.to_s.empty? || @tokens.include?(name)

      block_closure = block.nil? ? nil : proc { |x| instance_exec(x, &block) }
      @tokens[name] = { match: match, state: state, on_match: block_closure }
    end

    def delete_token(name)
      @tokens.delete(name)
    end

    def set_state(new_state)
      @state = new_state
    end

    def clear_state
      @state = nil
    end

    def toss
      @tokenize = @tokenize[..-2]
    end

    def tokenize(text)
      @tokenize = []
      pos = 0

      while pos < text.length
        t = next_token(text[pos..])
        break if t.nil?

        @tokenize << t
        pos += t.value.length
        @tokens[t.name][:on_match].call(t.value) unless @tokens[t.name][:on_match].nil?
      end

      @tokenize << Token.new(:EOF, :EOF)
    end

    private

    def next_token(text)
      matches = @tokens.map do |name, data|
        next unless data[:state] == @state

        s = nil
        Array(data[:match]).each do |m|
          m = text.match(m) if m.is_a?(Regexp)
          if text[0..m.to_s.length - 1] == m.to_s
            s = text[0..m.to_s.length - 1]
            break
          end
        end

        s.to_s.empty? ? nil : Token.new(name, s)
      end

      matches.delete_if { |x| x.nil? }
      raise StandardError, "Couldn't match any tokens with '#{text.length > 10 ? text[..10] + '...' : text}'" if matches.empty?

      matches.sort { |a,b| b.value.length <=> a.value.length }.first
    end
  end
end
