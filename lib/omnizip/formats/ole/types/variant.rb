# frozen_string_literal: true

require "date"

module Omnizip
  module Formats
    module Ole
      # OLE type serialization module
      #
      # Provides serialization and deserialization for OLE data types
      # including variant types, strings, timestamps, and GUIDs.
      module Types
        # Generic binary data handler
        class Data < String
          # Load from binary data
          def self.load(str)
            new(str)
          end

          # Dump to binary data
          def self.dump(str)
            str.to_s
          end
        end

        # Null-terminated ASCII string (VT_LPSTR)
        class Lpstr < String
          # Load from binary data
          def self.load(str)
            new(str.to_s.chomp("\x00"))
          end

          # Dump to binary data
          def self.dump(str)
            str.to_s
          end
        end

        # Null-terminated UTF-16LE string (VT_LPWSTR)
        class Lpwstr < String
          # Load from UTF-16LE binary data
          def self.load(str)
            return new("") if str.nil? || str.empty?

            # Force binary data to UTF-16LE encoding, then transcode to UTF-8
            # Strip null terminator (UTF-16 null = 2 bytes)
            decoded = str.dup.force_encoding(Encoding::UTF_16LE)
            decoded = decoded.chomp("\x00".encode(Encoding::UTF_16LE))
            decoded = decoded.encode(Encoding::UTF_8)
            new(decoded)
          end

          # Dump to UTF-16LE binary data
          def self.dump(str)
            return "\x00\x00".b if str.nil? || str.empty?

            # Encode UTF-8 to UTF-16LE and force to binary
            data = str.encode(Encoding::UTF_16LE).force_encoding(Encoding::ASCII_8BIT)
            # Add null terminator (single UTF-16 null character = 2 bytes)
            data + "\x00\x00".b
          end
        end

        # Windows FILETIME timestamp (VT_FILETIME)
        #
        # Represents time as 100-nanosecond intervals since January 1, 1601.
        class FileTime
          # Size in bytes
          SIZE = 8

          # Windows epoch (January 1, 1601)
          EPOCH = DateTime.new(1601, 1, 1)

          # @return [DateTime] The timestamp value
          attr_reader :value

          # Create FileTime from DateTime
          #
          # @param value [DateTime, Time, nil]
          def initialize(value = nil)
            @value = case value
                     when DateTime, nil
                       value
                     when Time
                       DateTime.new(value.year, value.month, value.day,
                                    value.hour, value.min, value.sec)
                     else
                       raise ArgumentError, "Invalid time value: #{value.class}"
                     end
          end

          # Load from binary data
          #
          # @param str [String] 8-byte FILETIME data
          # @return [FileTime, nil] Parsed timestamp or nil if zero
          def self.load(str)
            return nil if str.nil? || str.bytesize < SIZE

            low, high = str.unpack("V2")
            return nil if low.zero? && high.zero?

            # Convert 100-nanosecond intervals to seconds
            intervals = (high << 32) | low
            seconds = intervals / 10_000_000.0

            # Add to epoch
            begin
              value = EPOCH + (seconds / 86_400.0)
              new(value)
            rescue StandardError
              nil
            end
          end

          # Dump to binary data
          #
          # @param time [FileTime, DateTime, Time, nil]
          # @return [String] 8-byte FILETIME data
          def self.dump(time)
            return "\x00".b * SIZE if time.nil?

            case time
            when FileTime
              value = time.value
            when DateTime
              value = time
            when Time
              value = DateTime.new(time.year, time.month, time.day,
                                   time.hour, time.min, time.sec)
            else
              raise ArgumentError, "Invalid time argument: #{time.class}"
            end

            # Calculate nanoseconds since epoch
            days = (value - EPOCH).to_f
            nanoseconds = (days * 86_400_000_000_000).round

            high = nanoseconds >> 32
            low = nanoseconds & 0xFFFFFFFF

            [low, high].pack("V2")
          end

          # Convert to Time
          #
          # @return [Time]
          def to_time
            return nil if @value.nil?

            Time.new(@value.year, @value.month, @value.day,
                     @value.hour, @value.min, @value.sec)
          end

          # Convert to string
          #
          # @return [String]
          def to_s
            @value.to_s
          end

          # Inspect
          def inspect
            "#<#{self.class}: #{@value}>"
          end
        end

        # COM CLSID/GUID (VT_CLSID)
        #
        # 128-bit globally unique identifier.
        class Clsid < String
          # Size in bytes
          SIZE = 16

          # Pack format for GUID components
          PACK = "V v v CC C6"

          # Load from binary data
          #
          # @param str [String] 16-byte GUID data
          # @return [Clsid]
          def self.load(str)
            new(str.to_s)
          end

          # Dump to binary data
          #
          # @param guid [String, nil] GUID string or binary data
          # @return [String] 16-byte binary data
          def self.dump(guid)
            return "\x00".b * SIZE if guid.nil?

            # If it contains dashes, parse from string format
            guid.include?("-") ? parse(guid) : guid.to_s
          end

          # Parse from string format "{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}"
          #
          # @param str [String] GUID string
          # @return [Clsid]
          # @raise [ArgumentError] If format is invalid
          def self.parse(str)
            values = str.scan(/[a-f\d]+/i).map(&:hex)

            if values.length == 5
              # Split 4th and 5th groups into bytes
              values[3] = sprintf("%04x", values[3]).scan(/../).map(&:hex)
              values[4] = sprintf("%012x", values[4]).scan(/../).map(&:hex)
              guid = new(values.flatten.pack(PACK))

              if guid.format.delete("{}").downcase == str.downcase.delete("{}")
                return guid
              end
            end

            raise ArgumentError, "Invalid GUID format: #{str}"
          end

          # Format to human-readable string
          #
          # @return [String] "{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}"
          def format
            vals = unpack(PACK)
            # vals = [uint32, uint16, uint16, uint8, uint8, uint8, uint8, uint8, uint8, uint8, uint8]
            last_six = vals[5, 6].map { |b| sprintf("%02x", b) }.join
            sprintf("%08x-%04x-%04x-%02x%02x-%s", vals[0], vals[1], vals[2], vals[3], vals[4], last_six)
          end

          # Inspect
          def inspect
            "#<#{self.class}:{#{format}}>"
          end
        end

        # Variant type constants
        module Variant
          # Type ID to name mapping
          NAMES = {
            0x0000 => "VT_EMPTY",
            0x0001 => "VT_NULL",
            0x0002 => "VT_I2",
            0x0003 => "VT_I4",
            0x0004 => "VT_R4",
            0x0005 => "VT_R8",
            0x0006 => "VT_CY",
            0x0007 => "VT_DATE",
            0x0008 => "VT_BSTR",
            0x0009 => "VT_DISPATCH",
            0x000a => "VT_ERROR",
            0x000b => "VT_BOOL",
            0x000c => "VT_VARIANT",
            0x000d => "VT_UNKNOWN",
            0x000e => "VT_DECIMAL",
            0x0010 => "VT_I1",
            0x0011 => "VT_UI1",
            0x0012 => "VT_UI2",
            0x0013 => "VT_UI4",
            0x0014 => "VT_I8",
            0x0015 => "VT_UI8",
            0x0016 => "VT_INT",
            0x0017 => "VT_UINT",
            0x0018 => "VT_VOID",
            0x0019 => "VT_HRESULT",
            0x001a => "VT_PTR",
            0x001b => "VT_SAFEARRAY",
            0x001c => "VT_CARRAY",
            0x001d => "VT_USERDEFINED",
            0x001e => "VT_LPSTR",
            0x001f => "VT_LPWSTR",
            0x0040 => "VT_FILETIME",
            0x0041 => "VT_BLOB",
            0x0042 => "VT_STREAM",
            0x0043 => "VT_STORAGE",
            0x0044 => "VT_STREAMED_OBJECT",
            0x0045 => "VT_STORED_OBJECT",
            0x0046 => "VT_BLOB_OBJECT",
            0x0047 => "VT_CF",
            0x0048 => "VT_CLSID",
            0x0fff => "VT_ILLEGALMASKED",
            0x1000 => "VT_VECTOR",
            0x2000 => "VT_ARRAY",
            0x4000 => "VT_BYREF",
            0x8000 => "VT_RESERVED",
            0xffff => "VT_ILLEGAL",
          }.freeze

          # Type name to class mapping
          CLASS_MAP = {
            "VT_LPSTR" => Lpstr,
            "VT_LPWSTR" => Lpwstr,
            "VT_FILETIME" => FileTime,
            "VT_CLSID" => Clsid,
          }.freeze

          # Define type constants
          NAMES.each do |num, name|
            const_set name, num
          end

          # Additional constant
          VT_TYPEMASK = 0x0fff

          # Load variant value from binary data
          #
          # @param type [Integer] Variant type ID
          # @param str [String] Binary data
          # @return [Object] Deserialized value
          def self.load(type, str)
            type_name = NAMES[type]
            raise ArgumentError, "Unknown OLE type: 0x#{format('%04x', type)}" unless type_name

            klass = CLASS_MAP[type_name] || Data
            klass.load(str)
          end

          # Dump variant value to binary data
          #
          # @param type [Integer] Variant type ID
          # @param value [Object] Value to serialize
          # @return [String] Binary data
          def self.dump(type, value)
            type_name = NAMES[type]
            raise ArgumentError, "Unknown OLE type: 0x#{format('%04x', type)}" unless type_name

            klass = CLASS_MAP[type_name] || Data
            klass.dump(value)
          end
        end
      end
    end
  end
end
