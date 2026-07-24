# frozen_string_literal: true

module Omnizip
  module Formats
    module Zip
      # Info-ZIP Unix extra field (tag 0x7875)
      # Stores Unix-specific metadata including symbolic link targets
      class UnixExtraField
        UNIX_EXTRA_FIELD_TAG = 0x7875

        attr_accessor :version, :uid_size, :uid, :gid_size, :gid, :link_target

        def initialize(
          version: 1,
          uid: nil,
          gid: nil,
          link_target: nil
        )
          @version = version
          @uid = uid
          @gid = gid
          @link_target = link_target

          # Calculate sizes
          @uid_size = uid ? [uid].pack("V").bytesize : 0
          @gid_size = gid ? [gid].pack("V").bytesize : 0
        end

        # Check if this field contains a symbolic link target
        def symlink?
          !@link_target.nil? && !@link_target.empty?
        end

        # Serialize to binary format
        def to_binary
          data = [version].pack("C")

          # Add UID if present
          if @uid
            data << [@uid_size].pack("C")
            data << [@uid].pack("V")[0, @uid_size]
          else
            data << [0].pack("C")
          end

          # Add GID if present
          if @gid
            data << [@gid_size].pack("C")
            data << [@gid].pack("V")[0, @gid_size]
          else
            data << [0].pack("C")
          end

          # Add link target if present (for symbolic links)
          data << @link_target.b if @link_target

          # Return with tag and size
          [
            UNIX_EXTRA_FIELD_TAG,
            data.bytesize,
          ].pack("vv") + data
        end

        # Parse from binary data
        def self.from_binary(data)
          return nil if data.nil? || data.bytesize < 3

          version = data.unpack1("C")
          offset = 1

          # Read UID
          uid_size = data[offset].unpack1("C")
          offset += 1
          uid = (data[offset, uid_size].unpack1("V") if uid_size.positive?)
          offset += uid_size

          # Read GID
          gid_size = data[offset].unpack1("C")
          offset += 1
          gid = (data[offset, gid_size].unpack1("V") if gid_size.positive?)
          offset += gid_size

          # Read link target if present
          link_target = if offset < data.bytesize
                          data[offset..].force_encoding("UTF-8")
                        end

          new(
            version: version,
            uid: uid,
            gid: gid,
            link_target: link_target,
          )
        end

        # Parse extra field from complete extra field data
        def self.find_in_extra_field(extra_field_data)
          return nil if extra_field_data.nil? || extra_field_data.empty?

          offset = 0
          while offset < extra_field_data.bytesize - 4
            tag, size = extra_field_data[offset, 4].unpack("vv")

            if tag == UNIX_EXTRA_FIELD_TAG
              field_data = extra_field_data[offset + 4, size]
              return from_binary(field_data)
            end

            offset += 4 + size
          end

          nil
        end

        # Create a Unix extra field for a symbolic link
        def self.for_symlink(target, uid: nil, gid: nil)
          new(
            version: 1,
            uid: uid,
            gid: gid,
            link_target: target,
          )
        end

        # Create a Unix extra field for a hard link
        def self.for_hardlink(uid: nil, gid: nil)
          new(
            version: 1,
            uid: uid,
            gid: gid,
            link_target: nil,
          )
        end

        # Get the size of this extra field in bytes
        def size
          to_binary.bytesize
        end

        # Convert to hash representation
        def to_h
          {
            tag: UNIX_EXTRA_FIELD_TAG,
            version: @version,
            uid: @uid,
            gid: @gid,
            link_target: @link_target,
          }
        end
      end
    end
  end
end
