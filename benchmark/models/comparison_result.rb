# frozen_string_literal: true

require_relative "benchmark_result"

module Benchmark
  module Models
    # Represents a comparison between omnizip and 7-Zip results
    class ComparisonResult
      attr_reader :test_name, :omnizip_result, :seven_zip_result

      def initialize(test_name:, omnizip_result:, seven_zip_result:)
        @test_name = test_name
        @omnizip_result = omnizip_result
        @seven_zip_result = seven_zip_result
      end

      def size_difference_bytes
        return nil unless both_successful?

        omnizip_result.compressed_size - seven_zip_result.compressed_size
      end

      def size_difference_percentage
        return nil unless both_successful?

        ((size_difference_bytes.to_f / seven_zip_result.compressed_size) *
         100).round(2)
      end

      def compression_speed_ratio
        return nil unless both_successful?

        return nil if seven_zip_result.compression_time.nil? ||
                      seven_zip_result.compression_time.zero?

        (omnizip_result.compression_time /
         seven_zip_result.compression_time).round(2)
      end

      def decompression_speed_ratio
        return nil unless both_successful?

        return nil if seven_zip_result.decompression_time.nil? ||
                      seven_zip_result.decompression_time.zero?

        (omnizip_result.decompression_time /
         seven_zip_result.decompression_time).round(2)
      end

      def both_successful?
        omnizip_result.success? && seven_zip_result.success?
      end

      def to_h
        {
          test_name: test_name,
          omnizip: omnizip_result.to_h,
          seven_zip: seven_zip_result.to_h,
          comparison: {
            size_difference_bytes: size_difference_bytes,
            size_difference_percentage: size_difference_percentage,
            compression_speed_ratio: compression_speed_ratio,
            decompression_speed_ratio: decompression_speed_ratio
          }
        }
      end
    end
  end
end
