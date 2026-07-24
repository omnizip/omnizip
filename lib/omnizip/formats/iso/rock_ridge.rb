# frozen_string_literal: true

module Omnizip
  module Formats
    module Iso
      # Rock Ridge Extensions for ISO 9660
      #
      # Implements System Use Sharing Protocol (SUSP) and Rock Ridge
      # extensions to store Unix file attributes, permissions, symbolic links,
      # and device nodes in ISO 9660 images.
      #
      # Rock Ridge allows ISO images to preserve full Unix filesystem semantics.
      module RockRidge
        # SUSP/Rock Ridge signature identifiers
        module Signatures
          SP = "SP" # System Use Sharing Protocol indicator
          CE = "CE" # Continuation area
          PX = "PX" # POSIX file attributes
          PN = "PN" # POSIX device number
          SL = "SL" # Symbolic link
          NM = "NM" # Alternate name
          CL = "CL" # Child link
          PL = "PL" # Parent link
          RE = "RE" # Relocated directory
          TF = "TF" # Time stamps
          SF = "SF" # Sparse file
        end

        # System Use Entry
        class SUEntry
          attr_accessor :signature, :length, :version, :data

          # Initialize entry
          #
          # @param signature [String] 2-byte signature
          # @param version [Integer] Entry version
          # @param data [String] Entry data
          def initialize(signature, version: 1, data: "")
            @signature = signature
            @length = 4 + data.bytesize
            @version = version
            @data = data
          end

          # Convert to binary
          #
          # @return [String] Binary representation
          def to_binary
            result = +""
            result << @signature # 2 bytes
            result << [@length].pack("C")  # 1 byte
            result << [@version].pack("C") # 1 byte
            result << @data
            result
          end

          # Parse from binary
          #
          # @param data [String] Binary data
          # @param offset [Integer] Starting offset
          # @return [SUEntry] Parsed entry
          def self.parse(data, offset = 0)
            signature = data[offset, 2]
            length = data.getbyte(offset + 2)
            version = data.getbyte(offset + 3)
            entry_data = data[offset + 4, length - 4]

            new(signature, version: version, data: entry_data)
          end
        end

        # Add Rock Ridge extensions to directory record
        #
        # @param record_data [String] Directory record data
        # @param file_stat [File::Stat] File statistics
        # @param name [String] File name
        # @param is_symlink [Boolean] Is this a symbolic link
        # @return [String] Updated record with Rock Ridge fields
        def self.add_extensions(record_data, file_stat, name, is_symlink: false)
          system_use = +""

          # Add SP entry (first entry in root directory only)
          # This indicates Rock Ridge is being used
          # For simplicity, we'll add to all entries

          # Add PX (POSIX attributes)
          system_use << build_px_entry(file_stat).to_binary

          # Add TF (timestamps)
          system_use << build_tf_entry(file_stat).to_binary

          # Add NM (alternate name) if different from ISO name
          unless name == File.basename(name).upcase
            system_use << build_nm_entry(name).to_binary
          end

          # Add SL (symbolic link) if applicable
          if is_symlink
            link_target = File.readlink(file_stat)
            system_use << build_sl_entry(link_target).to_binary
          end

          # Append system use to record
          record_data + system_use
        end

        # Build PX (POSIX attributes) entry
        #
        # @param stat [File::Stat] File statistics
        # @return [SUEntry] PX entry
        def self.build_px_entry(stat)
          data = +""

          # File mode (both-endian)
          data << [stat.mode].pack("V")
          data << [stat.mode].pack("N")

          # Number of links (both-endian)
          data << [stat.nlink].pack("V")
          data << [stat.nlink].pack("N")

          # User ID (both-endian)
          data << [stat.uid].pack("V")
          data << [stat.uid].pack("N")

          # Group ID (both-endian)
          data << [stat.gid].pack("V")
          data << [stat.gid].pack("N")

          # Inode number (both-endian) - optional
          data << [stat.ino].pack("V")
          data << [stat.ino].pack("N")

          SUEntry.new(Signatures::PX, data: data)
        end

        # Build TF (timestamps) entry
        #
        # @param stat [File::Stat] File statistics
        # @return [SUEntry] TF entry
        def self.build_tf_entry(stat)
          # Flags indicating which timestamps are present
          # Bit 0: Creation time
          # Bit 1: Modify time
          # Bit 2: Access time
          # Bit 3: Attributes time
          # Bit 4: Backup time
          # Bit 5: Expiration time
          # Bit 6: Effective time
          # Bit 7: Long format (17 bytes instead of 7)

          flags = 0b00000110 # Modify and access times, short format

          data = +""
          data << [flags].pack("C")

          # Modification time (7-byte format)
          data << encode_time_7byte(stat.mtime)

          # Access time (7-byte format)
          data << encode_time_7byte(stat.atime)

          SUEntry.new(Signatures::TF, data: data)
        end

        # Build NM (alternate name) entry
        #
        # @param name [String] File name
        # @return [SUEntry] NM entry
        def self.build_nm_entry(name)
          # Flags
          # Bit 0: CONTINUE (name continues in next NM)
          # Bit 1: CURRENT (name is ".")
          # Bit 2: PARENT (name is "..")
          flags = 0

          data = +""
          data << [flags].pack("C")
          data << name

          SUEntry.new(Signatures::NM, data: data)
        end

        # Build SL (symbolic link) entry
        #
        # @param target [String] Link target
        # @return [SUEntry] SL entry
        def self.build_sl_entry(target)
          # Flags
          # Bit 0: CONTINUE (link continues in next SL)
          flags = 0

          data = +""
          data << [flags].pack("C")

          # Component flags
          # Bit 0: CONTINUE (component continues)
          # Bit 1: CURRENT (component is ".")
          # Bit 2: PARENT (component is "..")
          # Bit 3: ROOT (component is root)
          comp_flags = 0

          # Component length
          data << [comp_flags].pack("C")
          data << [target.bytesize].pack("C")
          data << target

          SUEntry.new(Signatures::SL, data: data)
        end

        # Build PN (POSIX device number) entry
        #
        # @param stat [File::Stat] File statistics
        # @return [SUEntry] PN entry
        def self.build_pn_entry(stat)
          data = +""

          # Device number high (both-endian)
          dev_high = (stat.rdev >> 32) & 0xFFFFFFFF
          data << [dev_high].pack("V")
          data << [dev_high].pack("N")

          # Device number low (both-endian)
          dev_low = stat.rdev & 0xFFFFFFFF
          data << [dev_low].pack("V")
          data << [dev_low].pack("N")

          SUEntry.new(Signatures::PN, data: data)
        end

        # Encode time in 7-byte format
        #
        # @param time [Time] Time to encode
        # @return [String] 7-byte encoded time
        def self.encode_time_7byte(time)
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

        # Parse Rock Ridge extensions from system use field
        #
        # @param system_use [String] System use field data
        # @return [Hash] Parsed attributes
        def self.parse_extensions(system_use)
          attributes = {}
          offset = 0

          while offset < system_use.bytesize
            entry = SUEntry.parse(system_use, offset)

            case entry.signature
            when Signatures::PX
              attributes[:posix] = parse_px_entry(entry)
            when Signatures::TF
              attributes[:times] = parse_tf_entry(entry)
            when Signatures::NM
              attributes[:name] = parse_nm_entry(entry)
            when Signatures::SL
              attributes[:symlink] = parse_sl_entry(entry)
            end

            offset += entry.length
          end

          attributes
        end

        # Parse PX entry
        #
        # @param entry [SUEntry] PX entry
        # @return [Hash] Parsed POSIX attributes
        def self.parse_px_entry(entry)
          data = entry.data
          {
            mode: data[0, 4].unpack1("V"),
            nlink: data[8, 4].unpack1("V"),
            uid: data[16, 4].unpack1("V"),
            gid: data[24, 4].unpack1("V"),
            ino: data[32, 4].unpack1("V"),
          }
        end

        # Parse TF entry
        #
        # @param entry [SUEntry] TF entry
        # @return [Hash] Parsed timestamps
        def self.parse_tf_entry(entry)
          # Parse based on flags
          flags = entry.data.getbyte(0)
          times = {}

          offset = 1
          if flags & 0x02 # Modify time
            times[:mtime] = parse_time_7byte(entry.data[offset, 7])
            offset += 7
          end

          if flags & 0x04 # Access time
            times[:atime] = parse_time_7byte(entry.data[offset, 7])
          end

          times
        end

        # Parse NM entry
        #
        # @param entry [SUEntry] NM entry
        # @return [String] Alternate name
        def self.parse_nm_entry(entry)
          entry.data[1..]
        end

        # Parse SL entry
        #
        # @param entry [SUEntry] SL entry
        # @return [String] Symbolic link target
        def self.parse_sl_entry(entry)
          # Skip flags byte, component flags, read length and target
          comp_len = entry.data.getbyte(2)
          entry.data[3, comp_len]
        end

        # Parse 7-byte time format
        #
        # @param data [String] 7-byte time data
        # @return [Time] Parsed time
        def self.parse_time_7byte(data)
          year = 1900 + data.getbyte(0)
          month = data.getbyte(1)
          day = data.getbyte(2)
          hour = data.getbyte(3)
          minute = data.getbyte(4)
          second = data.getbyte(5)

          Time.new(year, month, day, hour, minute, second)
        rescue ArgumentError
          Time.now
        end
      end
    end
  end
end
