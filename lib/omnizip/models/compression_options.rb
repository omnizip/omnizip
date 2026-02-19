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
    # Model representing compression operation options.
    #
    # This class encapsulates configuration options for compression
    # operations, including compression level, threading, and buffer sizes.
    class CompressionOptions
      attr_accessor :level, :dictionary_size, :num_fast_bytes, :match_finder,
                    :num_threads, :solid, :buffer_size

      def initialize(**kwargs)
        @level = 5
        @num_threads = 1
        @solid = false
        @buffer_size = 65_536

        kwargs.each do |key, value|
          instance_variable_set("@#{key}", value)
        end
      end

      def to_h
        {
          level: @level,
          dictionary_size: @dictionary_size,
          num_fast_bytes: @num_fast_bytes,
          match_finder: @match_finder,
          num_threads: @num_threads,
          solid: @solid,
          buffer_size: @buffer_size,
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
      # @return [CompressionOptions] Deserialized instance
      def self.from_json(json)
        data = JSON.parse(json)
        new(**data.transform_keys(&:to_sym))
      end
    end
  end
end
