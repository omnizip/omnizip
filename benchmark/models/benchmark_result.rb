# frozen_string_literal: true

module Benchmark
  module Models
    # Represents the result of a single benchmark test
    class BenchmarkResult
      attr_reader :algorithm, :input_size, :input_type, :compressed_size,
                  :compression_time, :decompression_time, :error

      def initialize(
        algorithm:,
        input_size:,
        input_type:,
        compressed_size: nil,
        compression_time: nil,
        decompression_time: nil,
        error: nil
      )
        @algorithm = algorithm
        @input_size = input_size
        @input_type = input_type
        @compressed_size = compressed_size
        @compression_time = compression_time
        @decompression_time = decompression_time
        @error = error
      end

      def success?
        error.nil?
      end

      def compression_ratio
        return nil unless success? && compressed_size && input_size.positive?

        input_size.to_f / compressed_size
      end

      def compression_percentage
        return nil unless compression_ratio

        (1.0 - (1.0 / compression_ratio)) * 100
      end

      def to_h
        {
          algorithm: algorithm,
          input_size: input_size,
          input_type: input_type,
          compressed_size: compressed_size,
          compression_time: compression_time,
          decompression_time: decompression_time,
          compression_ratio: compression_ratio,
          compression_percentage: compression_percentage,
          error: error
        }
      end
    end
  end
end
