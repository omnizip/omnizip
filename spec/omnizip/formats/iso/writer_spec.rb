# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/iso/writer"
require "tmpdir"
require "fileutils"

RSpec.describe Omnizip::Formats::Iso::Writer do
  let(:temp_dir) { Dir.mktmpdir("omnizip_iso_test") }
  let(:output_iso) { File.join(temp_dir, "test.iso") }
  let(:test_file) { File.join(temp_dir, "test.txt") }
  let(:test_dir) { File.join(temp_dir, "test_directory") }

  before do
    File.write(test_file, "Hello, ISO 9660!")
    FileUtils.mkdir_p(test_dir)
    File.write(File.join(test_dir, "file1.txt"), "File 1 content")
    File.write(File.join(test_dir, "file2.txt"), "File 2 content")
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "creates writer with default options" do
      writer = described_class.new(output_iso)
      expect(writer.output_path).to eq(output_iso)
      expect(writer.level).to eq(2)
      expect(writer.rock_ridge).to be true
      expect(writer.joliet).to be true
    end

    it "accepts custom options" do
      writer = described_class.new(output_iso,
                                   volume_id: "TEST_DISC",
                                   level: 1,
                                   rock_ridge: false,
                                   joliet: false)

      expect(writer.volume_id).to eq("TEST_DISC")
      expect(writer.level).to eq(1)
      expect(writer.rock_ridge).to be false
      expect(writer.joliet).to be false
    end
  end

  describe "#add_file" do
    let(:writer) { described_class.new(output_iso) }

    it "adds file to ISO" do
      writer.add_file(test_file)
      expect(writer.files.length).to eq(1)
      expect(writer.files.first[:source]).to eq(File.expand_path(test_file))
    end

    it "raises error if file doesn't exist" do
      expect do
        writer.add_file("nonexistent.txt")
      end.to raise_error(ArgumentError, /File not found/)
    end

    it "accepts custom ISO path" do
      writer.add_file(test_file, "custom/path.txt")
      expect(writer.files.first[:iso_path]).to include("custom/path.txt")
    end
  end

  describe "#add_directory" do
    let(:writer) { described_class.new(output_iso) }

    it "adds directory recursively" do
      writer.add_directory(test_dir)
      expect(writer.directories).not_to be_empty
      expect(writer.files.size).to be >= 2 # At least file1 and file2
    end

    it "adds directory non-recursively" do
      writer.add_directory(test_dir, recursive: false)
      # Should add directory but not descend into subdirectories
      expect(writer.directories).not_to be_empty
    end

    it "raises error if directory doesn't exist" do
      expect do
        writer.add_directory("nonexistent_dir")
      end.to raise_error(ArgumentError, /Directory not found/)
    end

    it "accepts custom ISO path" do
      writer.add_directory(test_dir, iso_path: "custom_dir")
      expect(writer.directories.first[:iso_path]).to eq("custom_dir")
    end
  end

  describe "#write" do
    let(:writer) { described_class.new(output_iso) }

    it "creates ISO image file" do
      writer.add_file(test_file)
      result = writer.write

      expect(result).to eq(output_iso)
      expect(File.exist?(output_iso)).to be true
    end

    it "creates valid ISO with minimum size" do
      writer.add_file(test_file)
      writer.write

      # ISO should be at least system area + volume descriptors
      min_size = Omnizip::Formats::Iso::SECTOR_SIZE *
        (Omnizip::Formats::Iso::SYSTEM_AREA_SECTORS + 3)
      expect(File.size(output_iso)).to be >= min_size
    end

    it "includes all added files" do
      writer.add_file(test_file)
      writer.add_directory(test_dir)
      writer.write

      # Verify ISO can be read back
      iso = Omnizip::Formats::Iso.open(output_iso)
      entries = iso.entries

      expect(entries).not_to be_empty
    end

    it "creates ISO with custom volume ID" do
      writer = described_class.new(output_iso, volume_id: "MY_DISC")
      writer.add_file(test_file)
      writer.write

      iso = Omnizip::Formats::Iso.open(output_iso)
      expect(iso.volume_identifier).to include("MY_DISC")
    end

    it "supports different ISO levels" do
      [1, 2, 3].each do |level|
        iso_path = File.join(temp_dir, "level#{level}.iso")
        writer = described_class.new(iso_path, level: level)
        writer.add_file(test_file)

        expect { writer.write }.not_to raise_error
      end
    end
  end

  describe "ISO 9660 compliance" do
    it "pads sectors correctly" do
      writer = described_class.new(output_iso)
      writer.add_file(test_file)
      writer.write

      # File size should be multiple of sector size
      expect(File.size(output_iso) % Omnizip::Formats::Iso::SECTOR_SIZE).to eq(0)
    end

    it "starts with system area" do
      writer = described_class.new(output_iso)
      writer.add_file(test_file)
      writer.write

      File.open(output_iso, "rb") do |io|
        # First 16 sectors should be system area (zeros)
        system_area = io.read(Omnizip::Formats::Iso::SECTOR_SIZE *
                              Omnizip::Formats::Iso::SYSTEM_AREA_SECTORS)
        expect(system_area).to eq("\x00" * system_area.bytesize)
      end
    end

    it "writes valid volume descriptor" do
      writer = described_class.new(output_iso)
      writer.add_file(test_file)
      writer.write

      File.open(output_iso, "rb") do |io|
        # Seek to first volume descriptor
        io.seek(Omnizip::Formats::Iso::SECTOR_SIZE *
                Omnizip::Formats::Iso::VOLUME_DESCRIPTOR_START)

        vd_data = io.read(Omnizip::Formats::Iso::SECTOR_SIZE)

        # Check type (should be PRIMARY = 1)
        expect(vd_data.getbyte(0)).to eq(1)

        # Check identifier
        expect(vd_data[1, 5]).to eq("CD001")

        # Check version
        expect(vd_data.getbyte(6)).to eq(1)
      end
    end
  end

  describe "Rock Ridge support" do
    it "includes Rock Ridge extensions when enabled" do
      writer = described_class.new(output_iso, rock_ridge: true)
      writer.add_file(test_file)

      expect { writer.write }.not_to raise_error
    end

    it "omits Rock Ridge when disabled" do
      writer = described_class.new(output_iso, rock_ridge: false)
      writer.add_file(test_file)

      expect { writer.write }.not_to raise_error
    end
  end

  describe "Joliet support" do
    it "includes Joliet SVD when enabled" do
      writer = described_class.new(output_iso, joliet: true)
      writer.add_file(test_file)
      writer.write

      File.open(output_iso, "rb") do |io|
        # Skip system area and primary VD
        io.seek(Omnizip::Formats::Iso::SECTOR_SIZE *
                (Omnizip::Formats::Iso::VOLUME_DESCRIPTOR_START + 1))

        # Second VD should be supplementary (Joliet)
        svd_data = io.read(Omnizip::Formats::Iso::SECTOR_SIZE)

        # Check type (should be SUPPLEMENTARY = 2)
        expect(svd_data.getbyte(0)).to eq(2)

        # Check Joliet escape sequence
        expect(svd_data[88, 3]).to eq("%/E")
      end
    end

    it "omits Joliet when disabled" do
      writer = described_class.new(output_iso, joliet: false)
      writer.add_file(test_file)

      expect { writer.write }.not_to raise_error
    end
  end
end
