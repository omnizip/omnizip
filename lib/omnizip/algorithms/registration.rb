# frozen_string_literal: true

# Algorithm registration - triggers autoload and registers all algorithms
# This file should be required after algorithms.rb which sets up autoloads

module Omnizip
  module Algorithms
    # Touch constants to trigger autoload, then register
    LZMA
    LZMA2
    PPMd7
    PPMd8
    BZip2
    Deflate
    Deflate64
    Zstandard
  end
end

# Now register all algorithms
Omnizip::AlgorithmRegistry.register(:lzma, Omnizip::Algorithms::LZMA)
Omnizip::Algorithms::LZMA2.register_algorithm if Omnizip::Algorithms::LZMA2.respond_to?(:register_algorithm)
Omnizip::AlgorithmRegistry.register(:ppmd7, Omnizip::Algorithms::PPMd7)
Omnizip::AlgorithmRegistry.register(:ppmd8, Omnizip::Algorithms::PPMd8)
Omnizip::AlgorithmRegistry.register(:bzip2, Omnizip::Algorithms::BZip2)
Omnizip::AlgorithmRegistry.register(:deflate, Omnizip::Algorithms::Deflate)
Omnizip::AlgorithmRegistry.register(:deflate64, Omnizip::Algorithms::Deflate64)
Omnizip::AlgorithmRegistry.register(:zstandard, Omnizip::Algorithms::Zstandard)
