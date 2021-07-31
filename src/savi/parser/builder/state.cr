require "pegmatite"

module Savi::Parser::Builder
  # This State is used mainly for keeping track of line numbers and ranges,
  # so that we can better populate a Source::Pos with all the info it needs.
  class State
    getter source

    def initialize(@source : Source)
      @row = 0
      @line_start = 0
      @line_finish =
        (@source.content.byte_index('\n') || @source.content.bytesize).as(Int32)
    end

    private def content
      @source.content
    end

    private def next_line
      @row += 1
      @line_start = @line_finish + 1
      @line_finish = (content.byte_index('\n', @line_start) || content.bytesize)
    end

    private def prev_line
      @row -= 1
      @line_finish = @line_start - 1
      @line_start = (content.byte_rindex('\n', @line_finish) || -1) + 1
    end

    def pos(token : Pegmatite::Token) : Source::Pos
      kind, start, finish = token

      while start < @line_start
        prev_line
      end
      while start > @line_finish
        next_line
      end
      if start < @line_start
        raise "whoops"
      end
      col = start - @line_start

      Source::Pos.new(
        @source, start, finish, @line_start, @line_finish, @row, col,
      )
    end

    def slice(token : Pegmatite::Token)
      kind, start, finish = token
      slice(start...finish)
    end

    def slice(range : Range)
      content.byte_slice(range.begin, range.size)
    end

    def slice_with_escapes(token : Pegmatite::Token)
      kind, start, finish = token
      slice_with_escapes(start...finish)
    end

    def slice_with_escapes(range : Range)
      string = slice(range)
      reader = Char::Reader.new(string)

      String.build string.bytesize do |result|
        while reader.pos < string.bytesize
          case reader.current_char
          when '\\'
            case reader.next_char
            when '\\' then result << '\\'
            when '\'' then result << '\''
            when '"' then result << '"'
            when 'b' then result << '\b'
            when 'f' then result << '\f'
            when 'n' then result << '\n'
            when 'r' then result << '\r'
            when 't' then result << '\t'
            when 'x' then
              byte_value = 0
              2.times do
                hex_char = reader.next_char
                hex_value =
                  if '0' <= hex_char <= '9'
                    hex_char - '0'
                  elsif 'a' <= hex_char <= 'f'
                    10 + (hex_char - 'a')
                  elsif 'A' <= hex_char <= 'F'
                    10 + (hex_char - 'A')
                  else
                    raise "invalid escape hex character: #{hex_char}"
                  end
                byte_value = 16 * byte_value + hex_value
              end
              result.write Bytes[byte_value]
            when 'u' then
              codepoint = 0
              4.times do
                hex_char = reader.next_char
                hex_value =
                  if '0' <= hex_char <= '9'
                    hex_char - '0'
                  elsif 'a' <= hex_char <= 'f'
                    10 + (hex_char - 'a')
                  elsif 'A' <= hex_char <= 'F'
                    10 + (hex_char - 'A')
                  else
                    raise "invalid unicode escape hex character: #{hex_char}"
                  end
                codepoint = 16 * codepoint + hex_value
              end
              result << codepoint
            else
              # Not a valid escape character - pass it on as a literal slash
              # followed by that literal character, as if not an escape.
              result << '\\'
              result << reader.current_char
            end
          else
            result << reader.current_char
          end
          reader.next_char
        end
      end
    end
  end
end
