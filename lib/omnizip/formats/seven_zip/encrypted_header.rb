# frozen_string_literal: true

require_relative "constants"

module Omnizip
  module Formats
    module SevenZip
      # Encrypted header model for .7z archives
      # Stores metadata for header encryption
      class EncryptedHeader
        include Constants

        attr_accessor :encrypted_data, :salt, :iv, :original_size, :crc

        # Initialize encrypted header
        #
        # @param encrypted_data [String] Encrypted header bytes
        # @param salt [String] PBKDF2 salt
        # @param iv [String] AES initialization vector
        # @param original_size [Integer] Size before encryption
        # @param crc [Integer, nil] CRC32 of encrypted data (optional)
        def initialize(encrypted_data: nil, salt: nil, iv: nil,
                       original_size: 0, crc: nil)
          @encrypted_data = encrypted_data
          @salt = salt
          @iv = iv
          @original_size = original_size
          @crc = crc
        end

        # Serialize encrypted header to binary format
        #
        # Format:
        #   - 1 byte: PropertyId::ENCODED_HEADER marker
        #   - 8 bytes: Encrypted data size (little-endian)
        #   - 16 bytes: Salt
        #   - 16 bytes: IV
        #   - 8 bytes: Original size (little-endian)
        #   - 4 bytes: CRC32 (optional, 0 if not set)
        #   - N bytes: Encrypted data
        #
        # @return [String] Binary representation
        def to_binary
          data = String.new(encoding: "BINARY")

          # Marker for encoded header
          data << [PropertyId::ENCODED_HEADER].pack("C")

          # Encrypted data size
          data << [@encrypted_data.bytesize].pack("Q<")

          # Encryption parameters
          data << @salt
          data << @iv

          # Original size
          data << [@original_size].pack("Q<")

          # CRC (0 if not set)
          data << [crc || 0].pack("V")

          # Encrypted data
          data << @encrypted_data

          data
        end

        # Parse encrypted header from binary data
        #
        # @param data [String] Binary data
        # @return [EncryptedHeader] Parsed header
        # @raise [RuntimeError] if data is invalid
        def self.from_binary(data)
          raise "Invalid encrypted header: too short" if data.bytesize < 54

          pos = 0

          # Check marker
          marker = data.getbyte(pos)
          pos += 1
          unless marker == PropertyId::ENCODED_HEADER
            raise "Invalid encrypted header marker: expected #{PropertyId::ENCODED_HEADER}, got #{marker}"
          end

          # Read encrypted data size
          encrypted_size = data[pos, 8].unpack1("Q<")
          pos += 8

          # Read salt
          salt = data[pos, 16]
          pos += 16

          # Read IV
          iv = data[pos, 16]
          pos += 16

          # Read original size
          original_size = data[pos, 8].unpack1("Q<")
          pos += 8

          # Read CRC
          crc = data[pos, 4].unpack1("V")
          pos += 4

          # Read encrypted data
          encrypted_data = data[pos, encrypted_size]

          new(
            encrypted_data: encrypted_data,
            salt: salt,
            iv: iv,
            original_size: original_size,
            crc: crc.zero? ? nil : crc,
          )
        end

        # Check if header is valid
        #
        # @return [Boolean] true if has all required fields
        def valid?
          !@encrypted_data.nil? &&
            !@salt.nil? &&
            !@iv.nil? &&
            @original_size.positive? &&
            @encrypted_data.bytesize.positive?
        end

        # Verify CRC if set
        #
        # @return [Boolean] true if CRC matches or not set
        def verify_crc
          return true if @crc.nil?

          require_relative "../../checksums/crc32"
          calc_crc = Omnizip::Checksums::Crc32.new
          calc_crc.update(@encrypted_data)
          calc_crc.value == @crc
        end
      end
    end
  end
end
