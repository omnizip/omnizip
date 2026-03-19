# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe "Omnizip::Formats::SevenZip.search_embedded" do
  # 7z signature: '7z' + BC AF 27 1C
  let(:signature) { "7z\xBC\xAF\x27\x1C".b }

  # Helper to build a minimal valid 7z Start Header at a given offset
  # Start Header structure (32 bytes):
  # - Bytes 0-5: Signature (6 bytes)
  # - Bytes 6-7: Version (major.minor) - must be 0.4
  # - Bytes 8-11: Start Header CRC32 (over bytes 12-31)
  # - Bytes 12-19: Next Header Offset (uint64 LE)
  # - Bytes 20-27: Next Header Size (uint64 LE)
  # - Bytes 28-31: Next Header CRC32
  def build_valid_7z_header(next_header_size: 16)
    header = String.new(encoding: "BINARY")

    # Signature + version
    header << signature
    header << [0, 4].pack("CC") # Version 0.4

    # Placeholder for CRC (4 bytes) - we'll fill this in
    header << [0].pack("V")

    # Next Header fields
    next_header_offset = 0 # Immediately after Start Header
    next_header_crc = 0x12345678 # Dummy CRC
    header << [next_header_offset].pack("Q<")
    header << [next_header_size].pack("Q<")
    header << [next_header_crc].pack("V")

    # Compute and insert CRC over bytes 12-31
    next_header_data = header.byteslice(12, 20)
    crc = Omnizip::Checksums::Crc32.new.tap do |c|
      c.update(next_header_data)
    end.finalize
    header[8, 4] = [crc].pack("V")

    header
  end

  # Build an invalid 7z header (wrong version)
  def build_invalid_version_header
    header = String.new(encoding: "BINARY")
    header << signature
    header << [0, 0].pack("CC") # Version 0.0 - INVALID
    header << ([0].pack("V") * 6) # Padding
    header
  end

  # Build an invalid 7z header (bad CRC)
  def build_invalid_crc_header
    header = String.new(encoding: "BINARY")
    header << signature
    header << [0, 4].pack("CC") # Valid version
    header << [0xDEADBEEF].pack("V") # Wrong CRC
    header << [0].pack("Q<") # Next header offset
    header << [16].pack("Q<") # Next header size
    header << [0].pack("V") # Next header CRC
    header
  end

  describe ".search_embedded" do
    it "returns nil for file with no 7z signature" do
      Tempfile.create(["test", ".bin"]) do |f|
        f.write("This is not a 7z file" * 100)
        f.flush

        result = Omnizip::Formats::SevenZip.search_embedded(f.path)
        expect(result).to be_nil
      end
    end

    it "finds valid 7z archive at offset 0" do
      Tempfile.create(["test", ".bin"]) do |f|
        header = build_valid_7z_header
        # Add some fake next header data
        f.write(header)
        f.write("\x00" * 16)
        f.flush

        result = Omnizip::Formats::SevenZip.search_embedded(f.path)
        expect(result).to eq(0)
      end
    end

    it "finds valid 7z archive embedded after prefix data" do
      Tempfile.create(["test", ".bin"]) do |f|
        # Write some prefix data (simulating a stub executable)
        prefix = "MZ#{'X' * 100}" # Fake PE header
        f.write(prefix)

        # Write valid 7z header
        header = build_valid_7z_header
        f.write(header)
        f.write("\x00" * 16) # Fake next header
        f.flush

        result = Omnizip::Formats::SevenZip.search_embedded(f.path)
        expect(result).to eq(prefix.bytesize)
      end
    end

    it "skips invalid signatures with wrong version (0.0)" do
      Tempfile.create(["test", ".bin"]) do |f|
        # Write an invalid signature (version 0.0)
        invalid_header = build_invalid_version_header
        f.write(invalid_header)

        # Write a valid signature after some padding
        f.write("PADDING" * 10)

        # Write valid 7z header
        valid_offset = f.pos
        header = build_valid_7z_header
        f.write(header)
        f.write("\x00" * 16)
        f.flush

        result = Omnizip::Formats::SevenZip.search_embedded(f.path)
        # Should skip the invalid one and find the valid one
        expect(result).to eq(valid_offset)
      end
    end

    it "skips signatures with invalid CRC" do
      Tempfile.create(["test", ".bin"]) do |f|
        # Write an invalid signature (bad CRC)
        invalid_header = build_invalid_crc_header
        f.write(invalid_header)

        # Write a valid signature after some padding
        f.write("PADDING" * 10)

        # Write valid 7z header
        valid_offset = f.pos
        header = build_valid_7z_header
        f.write(header)
        f.write("\x00" * 16)
        f.flush

        result = Omnizip::Formats::SevenZip.search_embedded(f.path)
        # Should skip the invalid one and find the valid one
        expect(result).to eq(valid_offset)
      end
    end

    it "handles multiple false positive signatures before finding valid one" do
      Tempfile.create(["test", ".bin"]) do |f|
        # Create a file with multiple embedded 7z signatures
        # First: version 0.0 (invalid)
        f.write(build_invalid_version_header)
        f.write("\x00" * 26) # Pad to complete 32-byte header

        # Second: bad CRC (invalid)
        f.write(build_invalid_crc_header)
        f.write("\x00" * 6) # Pad to complete 32-byte header

        # Third: valid archive
        valid_offset = f.pos
        f.write(build_valid_7z_header)
        f.write("\x00" * 16)

        # Fourth: another invalid one (truncated)
        f.write(signature)
        f.write("\x00" * 10) # Not enough for a full header
        f.flush

        result = Omnizip::Formats::SevenZip.search_embedded(f.path)
        expect(result).to eq(valid_offset)
      end
    end

    it "returns nil when all signatures are invalid" do
      Tempfile.create(["test", ".bin"]) do |f|
        # Write multiple invalid signatures
        f.write(build_invalid_version_header)
        f.write("\x00" * 26)
        f.write(build_invalid_crc_header)
        f.write("\x00" * 6)
        f.flush

        result = Omnizip::Formats::SevenZip.search_embedded(f.path)
        expect(result).to be_nil
      end
    end

    it "rejects signature where next_header_size exceeds file size" do
      Tempfile.create(["test", ".bin"]) do |f|
        header = String.new(encoding: "BINARY")
        header << signature
        header << [0, 4].pack("CC")

        # Placeholder CRC
        header << [0].pack("V")

        # Next header fields - claim a huge size that exceeds file
        header << [0].pack("Q<") # offset
        header << [0xFFFFFFFFFFFF].pack("Q<") # impossibly large size
        header << [0].pack("V")

        # Compute CRC (it will be valid, but size check should fail)
        next_header_data = header.byteslice(12, 20)
        crc = Omnizip::Checksums::Crc32.new.tap do |c|
          c.update(next_header_data)
        end.finalize
        header[8, 4] = [crc].pack("V")

        f.write(header)
        f.flush

        result = Omnizip::Formats::SevenZip.search_embedded(f.path)
        expect(result).to be_nil
      end
    end
  end

  describe ".valid_7z_start_header?" do
    it "returns true for valid header" do
      header = build_valid_7z_header
      data = header + ("\x00" * 16)
      file_size = data.bytesize

      result = Omnizip::Formats::SevenZip.valid_7z_start_header?(data, 0,
                                                                 file_size)
      expect(result).to be true
    end

    it "returns false for version 0.0" do
      header = build_invalid_version_header
      data = header.ljust(48, "\x00")
      file_size = data.bytesize

      result = Omnizip::Formats::SevenZip.valid_7z_start_header?(data, 0,
                                                                 file_size)
      expect(result).to be false
    end

    it "returns false for truncated header" do
      header = build_valid_7z_header
      # Only take first 20 bytes (not enough for 32-byte header)
      truncated = header.byteslice(0, 20)

      result = Omnizip::Formats::SevenZip.valid_7z_start_header?(truncated, 0,
                                                                 truncated.bytesize)
      expect(result).to be false
    end

    it "returns false for CRC mismatch" do
      header = build_invalid_crc_header
      data = header.ljust(48, "\x00")

      result = Omnizip::Formats::SevenZip.valid_7z_start_header?(data, 0,
                                                                 data.bytesize)
      expect(result).to be false
    end
  end
end
