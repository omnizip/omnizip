# frozen_string_literal: true

module Omnizip
  module Models
    # Configuration for split archive (multi-volume) creation
    # Defines how archives should be split into volumes
    class SplitOptions
      attr_accessor :volume_size, :naming_pattern, :span_strategy

      # Naming pattern types
      NAMING_NUMERIC = :numeric  # .001, .002, .003
      NAMING_ALPHA = :alpha      # .aa, .ab, .ac

      # Span strategies
      STRATEGY_FIRST_FIT = :first_fit  # Fill volumes sequentially
      STRATEGY_BALANCED = :balanced    # Balance files across volumes

      # Default volume size (100 MB)
      DEFAULT_VOLUME_SIZE = 100 * 1024 * 1024

      # Initialize with default options
      def initialize
        @volume_size = DEFAULT_VOLUME_SIZE
        @naming_pattern = NAMING_NUMERIC
        @span_strategy = STRATEGY_FIRST_FIT
      end

      # Parse volume size from string (e.g., "100M", "4.7G")
      #
      # @param size_str [String] Size string with unit
      # @return [Integer] Size in bytes
      def self.parse_volume_size(size_str)
        return size_str if size_str.is_a?(Integer)

        size_str = size_str.to_s.strip.upcase
        multiplier = case size_str
                     when /(\d+(?:\.\d+)?)\s*K(?:B)?$/
                       1024
                     when /(\d+(?:\.\d+)?)\s*M(?:B)?$/
                       1024 * 1024
                     when /(\d+(?:\.\d+)?)\s*G(?:B)?$/
                       1024 * 1024 * 1024
                     when /(\d+(?:\.\d+)?)\s*T(?:B)?$/
                       1024 * 1024 * 1024 * 1024
                     else
                       return size_str.to_i
                     end

        (Regexp.last_match(1).to_f * multiplier).to_i
      end

      # Generate volume filename
      #
      # @param base_path [String] Base archive path (e.g., "backup.7z.001")
      # @param volume_number [Integer] Volume number (1-based)
      # @return [String] Volume filename
      def volume_filename(base_path, volume_number)
        # Extract base and extension
        base = base_path.sub(/\.\d{3}$/, "")
        base = base.sub(/\.[a-z]{2,}$/, "") if @naming_pattern == NAMING_ALPHA

        case @naming_pattern
        when NAMING_NUMERIC
          format("%s.%03d", base, volume_number)
        when NAMING_ALPHA
          format("%s.%s", base, alpha_suffix(volume_number))
        else
          format("%s.%03d", base, volume_number)
        end
      end

      # Validate options
      #
      # @raise [ArgumentError] if options are invalid
      def validate!
        raise ArgumentError, "volume_size must be positive" unless
          @volume_size.positive?

        valid_patterns = [NAMING_NUMERIC, NAMING_ALPHA]
        unless valid_patterns.include?(@naming_pattern)
          raise ArgumentError,
                "naming_pattern must be one of #{valid_patterns.inspect}"
        end

        valid_strategies = [STRATEGY_FIRST_FIT, STRATEGY_BALANCED]
        unless valid_strategies.include?(@span_strategy)
          raise ArgumentError,
                "span_strategy must be one of #{valid_strategies.inspect}"
        end

        true
      end

      private

      # Generate alpha suffix for volume number
      #
      # @param volume_number [Integer] Volume number (1-based)
      # @return [String] Alpha suffix (aa, ab, ..., az, ba, ..., zz, aaa, ...)
      def alpha_suffix(volume_number)
        # Convert 1 -> aa, 2 -> ab, ..., 26 -> az, 27 -> ba, etc.
        num = volume_number - 1 # Convert to 0-based

        # For two-character format (minimum):
        # Second character cycles through a-z (rightmost, least significant)
        second = ("a".ord + (num % 26)).chr

        # First character represents which group of 26 we're in
        first_index = num / 26
        first = ("a".ord + first_index).chr

        first + second
      end
    end
  end
end
