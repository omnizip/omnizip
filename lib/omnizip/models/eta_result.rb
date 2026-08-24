# frozen_string_literal: true

#
# Copyright (C) 2025 Ribose Inc.
#

require "lutaml/model"

module Omnizip
  module Models
    # Model representing an ETA (Estimated Time to Arrival) calculation result.
    #
    # This class encapsulates the result of ETA calculations, including
    # seconds remaining, formatted time string, and confidence interval.
    #
    # Serialized via lutaml-model — no hand-rolled +to_h+ / +to_json+.
    class ETAResult < Lutaml::Model::Serializable
      # No mapping block: the default mapping already omits unassigned
      # attributes, which is what the previous +to_h+ did with +.compact+.
      attribute :seconds_remaining, :float
      attribute :formatted, :string
      attribute :confidence_lower, :float
      attribute :confidence_upper, :float

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
    end
  end
end
