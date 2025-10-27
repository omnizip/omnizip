# frozen_string_literal: true

# Copyright (C) 2025 Ribose Inc.

module Omnizip
  module Crypto
    class Aes256
      # Constants for AES-256 encryption in 7-Zip format
      module Constants
        # Key size for AES-256 (32 bytes = 256 bits)
        KEY_SIZE = 32

        # Maximum salt size (16 bytes)
        SALT_SIZE_MAX = 16
        SALT_SIZE = 16

        # IV size (16 bytes = AES block size)
        IV_SIZE = 16
        BLOCK_SIZE = 16

        # Default number of SHA-256 cycles (2^19 = 524288)
        DEFAULT_CYCLES_POWER = 19
        MIN_CYCLES_POWER = 0
        MAX_CYCLES_POWER = 24
      end
    end
  end
end
