# frozen_string_literal: true

module Omnizip
  module Formats
    module Iso
      # Joliet Extensions for ISO 9660
      #
      # Implements Microsoft's Joliet extensions to support long filenames
      # (up to 64 characters) and Unicode (UCS-2) encoding in ISO 9660 images.
      #
      # Joliet creates a parallel directory structure in a Supplementary Volume
      # Descriptor with UCS-2 encoded filenames, allowing Windows systems to
      # display proper long filenames while maintaining ISO 9660 compatibility.
      module Joliet
        # Joliet escape sequences for UCS-2 encoding
        # Level 1: %/@
        # Level 2: %/C
        # Level 3: %/E (most common, supports UCS-2)
        ESCAPE_SEQUENCE_LEVEL_3 = "%/E"

        # Maximum Joliet filename length in characters
        MAX_FILENAME_LENGTH = 64

        # Encode string to UCS-2 (UTF-16BE)
        #
        # @param str [String] String to encode
        # @param max_length [Integer] Maximum length in characters
        # @return [String] UCS-2 encoded string
        def self.encode_ucs2(str, max_length = MAX_FILENAME_LENGTH)
          # Truncate to max length
          str = str[0, max_length] if str.length > max_length

          # Encode to UTF-16BE (UCS-2)
          str.encode("UTF-16BE")
        rescue Encoding::UndefinedConversionError
          # Fallback to ASCII if conversion fails
          str.encode("UTF-16BE", undef: :replace, replace: "_")
        end

        # Decode UCS-2 string to UTF-8
        #
        # @param ucs2_data [String] UCS-2 encoded data
        # @return [String] UTF-8 string
        def self.decode_ucs2(ucs2_data)
          ucs2_data.force_encoding("UTF-16BE").encode("UTF-8")
        rescue Encoding::UndefinedConversionError
          # Fallback if decoding fails
          ucs2_data.force_encoding("UTF-16BE").encode("UTF-8",
                                                      undef: :replace,
                                                      replace: "?")
        end

        # Build Joliet directory record
        #
        # @param name [String] Entry name
        # @param entry_info [Hash] Entry information
        # @param is_directory [Boolean] Is this a directory
        # @return [String] Joliet directory record
        def self.build_directory_record(name, entry_info, is_directory: false)
          # Encode name to UCS-2
          name_ucs2 = encode_ucs2(name)
          name_len = name_ucs2.bytesize

          # Calculate record length
          # No padding needed for UCS-2 names (always even length)
          record_len = 33 + name_len

          record = +""

          # Byte 0: Length of directory record
          record << [record_len].pack("C")

          # Byte 1: Extended attribute record length
          record << [0].pack("C")

          # Bytes 2-9: Location of extent (both-endian)
          location = entry_info[:location] || 0
          record << [location].pack("V")
          record << [location].pack("N")

          # Bytes 10-17: Data length (both-endian)
          data_length = entry_info[:size] || 0
          record << [data_length].pack("V")
          record << [data_length].pack("N")

          # Bytes 18-24: Recording date and time
          mtime = entry_info[:mtime] || entry_info[:stat]&.mtime || Time.now
          record << encode_record_datetime(mtime)

          # Byte 25: File flags
          flags = 0
          flags |= Iso::FLAG_DIRECTORY if is_directory
          record << [flags].pack("C")

          # Byte 26: File unit size
          record << [0].pack("C")

          # Byte 27: Interleave gap size
          record << [0].pack("C")

          # Bytes 28-31: Volume sequence number (both-endian)
          record << [1].pack("v")
          record << [1].pack("n")

          # Byte 32: Length of file identifier
          record << [name_len].pack("C")

          # Bytes 33+: File identifier (UCS-2 encoded)
          record << name_ucs2

          record
        end

        # Sanitize filename for Joliet
        #
        # @param name [String] Original filename
        # @return [String] Sanitized filename
        def self.sanitize_filename(name)
          # Joliet allows most Unicode characters
          # Maximum 64 characters
          # Disallow: / * ? < > | " : \

          sanitized = name.gsub(/[\/*?<>|":\\]/, "_")
          if sanitized.length > MAX_FILENAME_LENGTH
            sanitized = sanitized[0,
                                  MAX_FILENAME_LENGTH]
          end
          sanitized
        end

        # Check if filename requires Joliet
        #
        # @param name [String] Filename
        # @return [Boolean] true if Joliet needed
        def self.requires_joliet?(name)
          # Check if name exceeds ISO 9660 Level 2 limits
          return true if name.length > 31

          # Check if name contains non-ASCII or lowercase
          return true if /[^A-Z0-9_.-]/.match?(name)

          # Check if name contains Unicode
          name.encoding != Encoding::ASCII && name.bytes.any? { |b| b > 127 }
        end

        # Build Joliet supplementary volume descriptor
        #
        # @param primary_vd [String] Primary volume descriptor data
        # @param root_dir [Hash] Root directory information
        # @return [String] Joliet SVD (2048 bytes)
        def self.build_supplementary_vd(primary_vd, _root_dir)
          # Start with primary VD as template
          svd = primary_vd.dup

          # Change type to supplementary
          svd[0] = [Iso::VD_SUPPLEMENTARY].pack("C")

          # Add Joliet escape sequence
          # Bytes 88-90: Escape sequences
          svd[88, 3] = ESCAPE_SEQUENCE_LEVEL_3

          # Encode volume identifier to UCS-2
          volume_id = primary_vd[40, 32].strip
          volume_id_ucs2 = encode_ucs2(volume_id, 16)
          svd[40, 32] = pad_ucs2_string(volume_id_ucs2, 32)

          # Update root directory record with UCS-2 name
          # Root is always "\x00" so no change needed

          svd
        end

        # Pad UCS-2 string to specified length
        #
        # @param ucs2_str [String] UCS-2 string
        # @param byte_length [Integer] Target length in bytes
        # @return [String] Padded string
        def self.pad_ucs2_string(ucs2_str, byte_length)
          if ucs2_str.bytesize > byte_length
            ucs2_str[0, byte_length]
          else
            ucs2_str + (" ".encode("UTF-16BE") * ((byte_length - ucs2_str.bytesize) / 2))
          end
        end

        # Encode recording date/time (7-byte format)
        #
        # @param time [Time] Time to encode
        # @return [String] 7-byte encoded time
        def self.encode_record_datetime(time)
          [
            time.year - 1900,
            time.month,
            time.day,
            time.hour,
            time.min,
            time.sec,
            0, # GMT offset
          ].pack("C7")
        end
      end
    end
  end
end
