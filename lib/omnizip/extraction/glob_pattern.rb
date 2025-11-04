# frozen_string_literal: true

module Omnizip
  module Extraction
    # Implements glob pattern matching for file paths
    #
    # Supports:
    # - * - Match any characters except /
    # - ** - Match any characters including /
    # - ? - Match single character
    # - [abc] - Character class
    # - [!abc] - Negated character class
    # - {a,b,c} - Alternation (brace expansion)
    class GlobPattern
      attr_reader :pattern

      # Initialize a new glob pattern
      #
      # @param pattern [String] Glob pattern string
      def initialize(pattern)
        @pattern = pattern.to_s
        @regex = compile_pattern
      end

      # Check if a filename matches the pattern
      #
      # @param filename [String] Filename to check
      # @return [Boolean]
      def match?(filename)
        @regex.match?(filename.to_s)
      end

      # Convert pattern to string
      #
      # @return [String]
      def to_s
        @pattern
      end

      private

      # Compile glob pattern to regex
      #
      # @return [Regexp]
      def compile_pattern
        # Convert glob to regex (handles braces internally)
        regex_pattern = glob_to_regex(@pattern)

        # Compile with case-insensitive flag on case-insensitive filesystems
        Regexp.new("\\A#{regex_pattern}\\z", case_sensitive? ? 0 : Regexp::IGNORECASE)
      end

      # Convert glob pattern to regex
      #
      # @param pattern [String] Glob pattern
      # @return [String] Regex pattern
      def glob_to_regex(pattern)
        result = String.new
        i = 0

        while i < pattern.length
          char = pattern[i]

          case char
          when "*"
            if pattern[i + 1] == "*"
              # ** matches everything including /
              result << ".*"
              i += 1
              # Skip following / if present (**/foo)
              i += 1 if pattern[i + 1] == "/"
            else
              # * matches everything except /
              result << "[^/]*"
            end
          when "?"
            # ? matches single character except /
            result << "[^/]"
          when "["
            # Character class
            j = i + 1
            j += 1 while j < pattern.length && pattern[j] != "]"
            if j < pattern.length
              class_content = pattern[(i + 1)...j]
              result << if class_content.start_with?("!")
                          # Negated class [!abc]
                          "[^#{Regexp.escape(class_content[1..])}]"
                        else
                          # Normal class [abc]
                          "[#{Regexp.escape(class_content)}]"
                        end
              i = j
            else
              # Unclosed bracket, treat as literal
              result << Regexp.escape(char)
            end
          when "{"
            # Brace expansion {a,b,c}
            j = i + 1
            j += 1 while j < pattern.length && pattern[j] != "}"
            if j < pattern.length
              alternatives = pattern[(i + 1)...j].split(",")
              # Convert each alternative recursively
              alt_patterns = alternatives.map { |alt| glob_to_regex(alt) }
              result << "(?:#{alt_patterns.join("|")})"
              i = j
            else
              # Unclosed brace, treat as literal
              result << Regexp.escape(char)
            end
          when "/"
            # Directory separator
            result << "/"
          else
            # Literal character
            result << Regexp.escape(char)
          end

          i += 1
        end

        result
      end

      # Check if filesystem is case-sensitive
      #
      # @return [Boolean]
      def case_sensitive?
        # On macOS and Windows, filesystems are typically case-insensitive
        # On Linux, they're typically case-sensitive
        case RUBY_PLATFORM
        when /darwin/, /mswin/, /mingw/, /cygwin/
          false
        else
          true
        end
      end
    end
  end
end
