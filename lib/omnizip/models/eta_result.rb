# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

module Omnizip
  module Models
    # Model representing an ETA (Estimated Time to Arrival) calculation result.
    #
    # This class encapsulates the result of ETA calculations, including
    # seconds remaining, formatted time string, and confidence interval.
    class ETAResult
      attr_accessor :seconds_remaining, :formatted, :confidence_lower,
                    :confidence_upper

      # Get confidence interval as array
      #
      # @return [Array<Float>] [lower, upper] bounds in seconds
      def confidence_interval
        [confidence_lower, confidence_upper]
      end

      # Check if ETA is reliable (confidence interval is reasonable)
      #
      # @return [Boolean] true if confidence interval is within 50% of estimate
      def reliable?
        unless seconds_remaining && confidence_lower && confidence_upper
          return false
        end

        range = confidence_upper - confidence_lower
        range < (seconds_remaining * 0.5)
      end

      def to_h
        {
          seconds_remaining: @seconds_remaining,
          formatted: @formatted,
          confidence_lower: @confidence_lower,
          confidence_upper: @confidence_upper,
        }.compact
      end
    end
  end
end
