# frozen_string_literal: true

module Omnizip
  module Formats
    module Rar
      module Rar5
        # CRC32 calculation for RAR5 format
        class CRC32
          POLYNOMIAL = 0xEDB88320

          # Generate CRC32 lookup table
          def self.generate_table
            @generate_table ||= (0..255).map do |i|
              crc = i
              8.times do
                crc = (crc >> 1) ^ ((crc & 1) * POLYNOMIAL)
              end
              crc
            end
          end

          # Calculate CRC32 for data
          # @param data [String] Binary data
          # @return [Integer] 32-bit CRC
          def self.calculate(data)
            table = generate_table
            crc = 0xFFFFFFFF

            data.bytes.each do |byte|
              crc = (crc >> 8) ^ table[(crc ^ byte) & 0xFF]
            end

            crc ^ 0xFFFFFFFF
          end
        end
      end
    end
  end
end
