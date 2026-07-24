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

module Omnizip
  # Output formatting utilities for CLI commands.
  #
  # Provides methods for formatting compression statistics, error messages,
  # and other CLI output in a user-friendly manner.
  module CliOutputFormatter
    class << self
      # Format compression statistics for display.
      #
      # @param input_size [Integer] Original size in bytes
      # @param output_size [Integer] Compressed size in bytes
      # @param elapsed_time [Float] Time taken in seconds
      # @return [String] Formatted statistics
      def format_compression_stats(input_size, output_size, elapsed_time)
        ratio = if input_size.positive?
                  (output_size.to_f / input_size * 100).round(2)
                else
                  0.0
                end

        [
          "Input size:  #{format_size(input_size)}",
          "Output size: #{format_size(output_size)}",
          "Ratio:       #{ratio}%",
          "Time:        #{elapsed_time.round(3)}s",
        ].join("\n")
      end

      # Format file size in human-readable format.
      #
      # @param bytes [Integer] Size in bytes
      # @return [String] Formatted size
      def format_size(bytes)
        units = %w[B KB MB GB TB]
        return "0 B" if bytes.zero?

        exp = (Math.log(bytes) / Math.log(1024)).floor
        exp = [exp, units.length - 1].min

        size = (bytes.to_f / (1024**exp)).round(2)
        "#{size} #{units[exp]}"
      end

      # Format error message for display.
      #
      # @param error [Exception] The error object
      # @return [String] Formatted error message
      def format_error(error)
        "Error: #{error.message}"
      end

      # Format algorithm information as a table.
      #
      # @param algorithms [Array<Models::AlgorithmMetadata>] Algorithms
      # @return [String] Formatted table
      def format_algorithms_table(algorithms)
        return "No algorithms registered." if algorithms.empty?

        lines = []
        lines << "Available compression algorithms:"
        lines << ""

        max_name = algorithms.map { |a| a.name.to_s.length }.max
        max_desc = algorithms.map { |a| a.description.length }.max

        algorithms.each do |algo|
          name = algo.name.to_s.ljust(max_name)
          desc = algo.description.ljust(max_desc)
          version = "v#{algo.version}"
          lines << "  #{name} - #{desc} (#{version})"
        end

        lines.join("\n")
      end

      # Print verbose message if verbose mode is enabled.
      #
      # @param message [String] The message to print
      # @param verbose [Boolean] Whether verbose mode is enabled
      # @return [void]
      def verbose_puts(message, verbose)
        puts message if verbose
      end
    end
  end
end
