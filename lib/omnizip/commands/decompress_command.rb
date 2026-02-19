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

require_relative "../cli/output_formatter"

module Omnizip
  module Commands
    # Command to decompress files using specified algorithm.
    class DecompressCommand
      attr_reader :options

      # Initialize decompress command with options.
      #
      # @param options [Hash] Command options from Thor
      def initialize(options = {})
        @options = options
      end

      # Execute the decompress command.
      #
      # @param input_file [String] Path to input file
      # @param output_file [String] Path to output file
      # @return [void]
      def run(input_file, output_file)
        validate_inputs(input_file, output_file)

        algorithm_name = options[:algorithm] || detect_algorithm
        verbose = options[:verbose] || false

        CliOutputFormatter.verbose_puts(
          "Decompressing #{input_file} to #{output_file}...",
          verbose,
        )
        CliOutputFormatter.verbose_puts(
          "Algorithm: #{algorithm_name}",
          verbose,
        )

        start_time = Time.now

        decompress_file(input_file, output_file, algorithm_name)

        elapsed = Time.now - start_time

        input_size = File.size(input_file)
        output_size = File.size(output_file)

        if verbose
          puts ""
          puts CliOutputFormatter.format_compression_stats(
            output_size,
            input_size,
            elapsed,
          )
        else
          puts "Decompressed: #{input_file} -> #{output_file}"
        end
      end

      private

      def validate_inputs(input_file, output_file)
        unless File.exist?(input_file)
          raise Omnizip::IOError, "Input file not found: #{input_file}"
        end

        unless File.readable?(input_file)
          raise Omnizip::IOError,
                "Input file not readable: #{input_file}"
        end

        output_dir = File.dirname(output_file)
        unless File.directory?(output_dir)
          raise Omnizip::IOError,
                "Output directory does not exist: #{output_dir}"
        end

        return if File.writable?(output_dir)

        raise Omnizip::IOError,
              "Output directory not writable: #{output_dir}"
      end

      def detect_algorithm
        "lzma"
      end

      def decompress_file(input_file, output_file, algorithm_name)
        algorithm_class = AlgorithmRegistry.get(algorithm_name.to_sym)
        algorithm = algorithm_class.new

        File.open(input_file, "rb") do |input|
          File.open(output_file, "wb") do |output|
            algorithm.decompress(input, output)
          end
        end
      rescue UnknownAlgorithmError => e
        raise e
      rescue StandardError => e
        raise Omnizip::CompressionError,
              "Failed to decompress file: #{e.message}"
      end
    end
  end
end
