# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/iso"
require "tempfile"
require "fileutils"

RSpec.describe Omnizip::Formats::Iso do
  let(:test_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "VolumeDescriptor" do
    it "parses primary volume descriptor" do
      # Create minimal primary VD
      data = "\x01"                    # Type: Primary
      data += "CD001"                   # Identifier
      data += "\x01"                    # Version
      data += "\x00"                    # Unused
      data += " " * 32                  # System ID
      data += "TEST_VOLUME".ljust(32)  # Volume ID
      data += "\x00" * 8                # Unused
      data += [100].pack("V")           # Volume space size (LE)
      data += [100].pack("N")           # Volume space size (BE)
      data += "\x00" * (2048 - data.bytesize)  # Pad to sector size

      vd = Omnizip::Formats::Iso::VolumeDescriptor.parse(data)

      expect(vd.primary?).to be true
      expect(vd.identifier).to eq("CD001")
      expect(vd.volume_identifier).to eq("TEST_VOLUME")
      expect(vd.volume_space_size).to eq(100)
    end

    it "detects volume descriptor terminator" do
      data = "\xFF"                    # Type: Terminator
      data += "CD001"                   # Identifier
      data += "\x01"                    # Version
      data += "\x00" * (2048 - data.bytesize)

      vd = Omnizip::Formats::Iso::VolumeDescriptor.parse(data)

      expect(vd.terminator?).to be true
      expect(vd.primary?).to be false
    end

    it "raises error for invalid identifier" do
      data = "\x01INVALID\x01"
      data += "\x00" * (2048 - data.bytesize)

      expect do
        Omnizip::Formats::Iso::VolumeDescriptor.parse(data)
      end.to raise_error(/Invalid ISO identifier/)
    end
  end

  describe "DirectoryRecord" do
    it "parses directory record" do
      data = [34].pack("C")              # Length
      data += "\x00"                      # Extended attr length
      data += [10].pack("V")              # Location (LE)
      data += [10].pack("N")              # Location (BE)
      data += [1024].pack("V")            # Data length (LE)
      data += [1024].pack("N")            # Data length (BE)
      data += [2023 - 1900, 12, 25, 10, 30, 0, 0].pack("C*")  # Date
      data += [Omnizip::Formats::Iso::FLAG_DIRECTORY].pack("C")  # Flags
      data += "\x00\x00"                  # File unit size, interleave gap
      data += [1].pack("v")               # Volume sequence (LE)
      data += [1].pack("n")               # Volume sequence (BE)
      data += [4].pack("C")               # Name length
      data += "TEST"                      # Name

      record = Omnizip::Formats::Iso::DirectoryRecord.parse(data)

      expect(record.name).to eq("TEST")
      expect(record.directory?).to be true
      expect(record.size).to eq(1024)
      expect(record.location).to eq(10)
    end

    it "identifies current directory" do
      data = [34].pack("C")
      data += "\x00"
      data += [0].pack("V") + [0].pack("N")
      data += [0].pack("V") + [0].pack("N")
      data += "\x00" * 7
      data += [0].pack("C")
      data += "\x00\x00"
      data += [1].pack("v") + [1].pack("n")
      data += [1].pack("C")
      data += "\x00"  # Current directory marker

      record = Omnizip::Formats::Iso::DirectoryRecord.parse(data)
      expect(record.current_directory?).to be true
    end

    it "identifies parent directory" do
      data = [34].pack("C")
      data += "\x00"
      data += [0].pack("V") + [0].pack("N")
      data += [0].pack("V") + [0].pack("N")
      data += "\x00" * 7
      data += [0].pack("C")
      data += "\x00\x00"
      data += [1].pack("v") + [1].pack("n")
      data += [1].pack("C")
      data += "\x01"  # Parent directory marker

      record = Omnizip::Formats::Iso::DirectoryRecord.parse(data)
      expect(record.parent_directory?).to be true
    end
  end

  describe "PathTable" do
    it "parses path table entries" do
      # Root entry
      data = [1].pack("C")              # Name length
      data += "\x00"                     # Extended attr
      data += [20].pack("V")             # Location
      data += [1].pack("v")              # Parent
      data += "/"                        # Name
      data += "\x00"                     # Padding

      # Subdirectory entry
      data += [4].pack("C")              # Name length
      data += "\x00"                     # Extended attr
      data += [30].pack("V")             # Location
      data += [1].pack("v")              # Parent (root)
      data += "TEST"                     # Name

      pt = Omnizip::Formats::Iso::PathTable.parse(data, data.bytesize)

      expect(pt.entries.size).to eq(2)
      expect(pt.root.name).to eq("/")
      expect(pt.entries[1].name).to eq("TEST")
      expect(pt.entries[1].parent_directory_number).to eq(1)
    end

    it "finds entries by name" do
      data = [4].pack("C") + "\x00" + [20].pack("V") + [1].pack("v") + "TEST"
      pt = Omnizip::Formats::Iso::PathTable.parse(data, data.bytesize)

      entry = pt.find_by_name("TEST")
      expect(entry).not_to be_nil
      expect(entry.location).to eq(20)
    end
  end

  describe "Reader" do
    it "requires valid ISO file" do
      invalid_file = File.join(test_dir, "invalid.iso")
      File.write(invalid_file, "not an ISO")

      reader = Omnizip::Formats::Iso::Reader.new(invalid_file)
      expect { reader.open }.to raise_error
    end
  end

  describe "Module methods" do
    it "provides convenience methods" do
      expect(Omnizip::Formats::Iso).to respond_to(:open)
      expect(Omnizip::Formats::Iso).to respond_to(:list)
      expect(Omnizip::Formats::Iso).to respond_to(:extract)
      expect(Omnizip::Formats::Iso).to respond_to(:info)
    end
  end

  describe "Constants" do
    it "defines ISO 9660 constants" do
      expect(Omnizip::Formats::Iso::SECTOR_SIZE).to eq(2048)
      expect(Omnizip::Formats::Iso::SYSTEM_AREA_SECTORS).to eq(16)
      expect(Omnizip::Formats::Iso::VD_PRIMARY).to eq(1)
      expect(Omnizip::Formats::Iso::VD_TERMINATOR).to eq(255)
    end

    it "defines file flags" do
      expect(Omnizip::Formats::Iso::FLAG_DIRECTORY).to eq(0x02)
      expect(Omnizip::Formats::Iso::FLAG_HIDDEN).to eq(0x01)
    end
  end
end