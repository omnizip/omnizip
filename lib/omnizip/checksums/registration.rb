# frozen_string_literal: true

# Checksum registration - triggers autoload and registers all checksums
# This file should be required after checksums.rb which sets up autoloads

module Omnizip
  module Checksums
    # Touch constants to trigger autoload
    Crc32
    Crc64
  end
end

# Register checksum algorithms
Omnizip::ChecksumRegistry.register(:crc32, Omnizip::Checksums::Crc32)
Omnizip::ChecksumRegistry.register(:crc64, Omnizip::Checksums::Crc64)
