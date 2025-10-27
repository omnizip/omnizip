# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.

require "digest/sha2"
require_relative "constants"

module Omnizip
  module Crypto
    class Aes256
      # 7-Zip password-based key derivation
      #
      # Uses SHA-256 iterative hashing to derive encryption keys
      # from passwords. The number of iterations is 2^cycles_power.
      class KeyDerivation
        include Constants

        # Derive AES-256 key from password
        #
        # This implements 7-Zip's key derivation:
        # 1. Concatenate salt and password
        # 2. Hash with SHA-256 for 2^cycles_power iterations
        # 3. Extract first 32 bytes as key
        #
        # @param password [String] User password
        # @param salt [String] Random salt
        # @param cycles_power [Integer] Power of 2 for iterations
        # @return [String] 32-byte AES-256 key
        def self.derive_key(password, salt, cycles_power = DEFAULT_CYCLES_POWER)
          validate_inputs(password, salt, cycles_power)

          # Calculate number of iterations
          num_cycles = 1 << cycles_power

          # Initial input: salt + password (in UTF-16LE for 7-Zip compat)
          # Force binary encoding to make concatenation work
          encoded_password = encode_password(password).force_encoding(Encoding::BINARY)
          input = salt.dup.force_encoding(Encoding::BINARY) + encoded_password

          # Iterative SHA-256 hashing
          key = perform_hashing(input, num_cycles)

          # Return first 32 bytes
          key[0, KEY_SIZE]
        end

        # Validate key derivation inputs
        #
        # @param password [String] Password to validate
        # @param salt [String] Salt to validate
        # @param cycles_power [Integer] Cycles power to validate
        # @return [void]
        # @raise [ArgumentError] If inputs are invalid
        def self.validate_inputs(password, salt, cycles_power)
          if password.nil? || password.empty?
            raise ArgumentError,
                  "Password cannot be empty"
          end
          if salt.bytesize != SALT_SIZE
            raise ArgumentError,
                  "Salt must be #{SALT_SIZE} bytes"
          end

          return if cycles_power.between?(MIN_CYCLES_POWER, MAX_CYCLES_POWER)

          raise ArgumentError,
                "Cycles power must be between #{MIN_CYCLES_POWER} and #{MAX_CYCLES_POWER}"
        end

        # Encode password to UTF-16LE (7-Zip format)
        #
        # @param password [String] Password in any encoding
        # @return [String] UTF-16LE encoded password
        def self.encode_password(password)
          password.encode(Encoding::UTF_16LE)
        end

        # Perform iterative SHA-256 hashing
        #
        # @param input [String] Initial input (salt + password)
        # @param num_cycles [Integer] Number of hash iterations
        # @return [String] Final hash result
        def self.perform_hashing(input, num_cycles)
          digest = Digest::SHA256.new
          result = input

          num_cycles.times do
            digest.reset
            digest << result
            result = digest.digest
          end

          result
        end

        private_class_method :validate_inputs, :encode_password,
                             :perform_hashing
      end
    end
  end
end
