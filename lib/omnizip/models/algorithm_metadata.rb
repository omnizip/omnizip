# frozen_string_literal: true

#
# Copyright (C) 2024 Ribose Inc.
#
# This file is part of Omnizip.
#
# Omnizip is a pure Ruby port of 7-Zip compression algorithms.
# Based on the 7-Zip LZMA SDK by Igor Pavlov.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# See the COPYING file for the complete text of the license.
#

require "json"

module Omnizip
  module Models
    # Model representing metadata about a compression algorithm.
    #
    # This class encapsulates information about a compression algorithm,
    # including its name, description, version, and capabilities.
    class AlgorithmMetadata
      attr_accessor :name, :description, :version, :author,
                    :max_compression_level, :min_compression_level,
                    :default_compression_level, :supports_streaming,
                    :supports_multithreading

      def initialize(**kwargs)
        @supports_streaming = false
        @supports_multithreading = false

        kwargs.each do |key, value|
          instance_variable_set("@#{key}", value)
        end
      end

      def to_h
        {
          name: @name,
          description: @description,
          version: @version,
          author: @author,
          max_compression_level: @max_compression_level,
          min_compression_level: @min_compression_level,
          default_compression_level: @default_compression_level,
          supports_streaming: @supports_streaming,
          supports_multithreading: @supports_multithreading,
        }.compact
      end

      # Serialize to JSON
      #
      # @return [String] JSON representation
      def to_json(*args)
        to_h.to_json(*args)
      end

      # Deserialize from JSON
      #
      # @param json [String] JSON string
      # @return [AlgorithmMetadata] Deserialized instance
      def self.from_json(json)
        data = JSON.parse(json)
        new(**data.transform_keys(&:to_sym))
      end
    end
  end
end
