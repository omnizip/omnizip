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
  class AlgorithmRegistry < Omnizip::Registry
    BUILTIN_ALGORITHMS = {
      lzma: "Omnizip::Algorithms::LZMA",
      lzma2: "Omnizip::Algorithms::LZMA2",
      ppmd7: "Omnizip::Algorithms::PPMd7",
      ppmd8: "Omnizip::Algorithms::PPMd8",
      bzip2: "Omnizip::Algorithms::BZip2",
      deflate: "Omnizip::Algorithms::Deflate",
      deflate64: "Omnizip::Algorithms::Deflate64",
      zstandard: "Omnizip::Algorithms::Zstandard",
    }.freeze

    class << self
      def not_found_error_class
        Omnizip::UnknownAlgorithmError
      end

      def label
        "Algorithm"
      end

      def register(name, klass)
        raise ArgumentError, "Algorithm name cannot be nil" if name.nil?
        raise ArgumentError, "Algorithm class cannot be nil" if klass.nil?

        super
      end
    end
  end
end

# Lazy triggers: when +AlgorithmRegistry.get(:lzma)+ is called before the
# LZMA file has been autoloaded, the trigger references the constant
# (which autoloads the file), and the file's body self-registers.
Omnizip::AlgorithmRegistry::BUILTIN_ALGORITHMS.each do |name, const_path|
  Omnizip::AlgorithmRegistry.register_lazy(name) { Object.const_get(const_path) }
end
