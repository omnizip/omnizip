# frozen_string_literal: true

module Omnizip
  class ChecksumRegistry < Omnizip::Registry
    BUILTIN_CHECKSUMS = {
      crc32: "Omnizip::Checksums::Crc32",
      crc64: "Omnizip::Checksums::Crc64",
    }.freeze

    class << self
      def not_found_error_class
        Omnizip::UnknownChecksumError
      end

      def label
        "Checksum"
      end

      def register(name, checksum_class)
        key = normalize_key(name)
        existing = storage[key]
        if existing && existing != checksum_class
          raise ArgumentError, "Checksum '#{key}' is already registered"
        end

        synchronize { storage[key] = checksum_class }
        checksum_class
      end

      def available
        super.sort
      end
    end
  end
end

Omnizip::ChecksumRegistry::BUILTIN_CHECKSUMS.each do |name, const_path|
  Omnizip::ChecksumRegistry.register_lazy(name) { Object.const_get(const_path) }
end
