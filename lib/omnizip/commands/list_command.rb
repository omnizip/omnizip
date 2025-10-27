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
    # Command to list available compression algorithms.
    class ListCommand
      attr_reader :options

      # Initialize list command with options.
      #
      # @param options [Hash] Command options from Thor
      def initialize(options = {})
        @options = options
      end

      # Execute the list command.
      #
      # @return [void]
      def run
        algorithms = fetch_algorithms
        output = CliOutputFormatter.format_algorithms_table(algorithms)
        puts output
      end

      private

      def fetch_algorithms
        AlgorithmRegistry.available.map do |name|
          algorithm_class = AlgorithmRegistry.get(name)
          algorithm_class.metadata
        end
      end
    end
  end
end
