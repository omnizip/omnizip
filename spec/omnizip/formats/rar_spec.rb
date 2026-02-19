# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar"
require "tempfile"
require "fileutils"

RSpec.describe Omnizip::Formats::Rar do
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir) if temp_dir && File.exist?(temp_dir)
  end

  describe ".available?" do
    it "checks if RAR extraction is available" do
      result = described_class.available?
      expect([true, false]).to include(result)
    end
  end

  describe ".decompressor_info" do
    it "returns decompressor information" do
      info = described_class.decompressor_info
      expect(info).to be_a(Hash)
      expect(info).to have_key(:type)
      expect(info).to have_key(:version)
      expect(%i[gem command none]).to include(info[:type])
    end
  end

  describe "Decompressor" do
    describe ".available?" do
      it "returns boolean for availability" do
        result = Omnizip::Formats::Rar::Decompressor.available?
        expect([true, false]).to include(result)
      end
    end

    describe ".gem_available?" do
      it "checks if unrar gem is available" do
        result = Omnizip::Formats::Rar::Decompressor.gem_available?
        expect([true, false]).to include(result)
      end
    end

    describe ".command_available?" do
      it "checks if unrar command is available" do
        result = Omnizip::Formats::Rar::Decompressor.command_available?
        expect([true, false]).to include(result)
      end
    end

    describe ".command_path" do
      it "returns command path or nil" do
        path = Omnizip::Formats::Rar::Decompressor.command_path
        expect([String, NilClass]).to include(path.class)
      end
    end
  end

  describe "Constants" do
    it "defines RAR4 signature" do
      expect(Omnizip::Formats::Rar::Constants::RAR4_SIGNATURE).to eq(
        [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00],
      )
    end

    it "defines RAR5 signature" do
      expect(Omnizip::Formats::Rar::Constants::RAR5_SIGNATURE).to eq(
        [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00],
      )
    end

    it "defines block types" do
      constants = Omnizip::Formats::Rar::Constants
      expect(constants::BLOCK_MARKER).to eq(0x72)
      expect(constants::BLOCK_ARCHIVE).to eq(0x73)
      expect(constants::BLOCK_FILE).to eq(0x74)
    end

    it "defines archive flags" do
      constants = Omnizip::Formats::Rar::Constants
      expect(constants::ARCHIVE_VOLUME).to eq(0x0001)
      expect(constants::ARCHIVE_SOLID).to eq(0x0008)
      expect(constants::ARCHIVE_LOCKED).to eq(0x0004)
    end

    it "defines file flags" do
      constants = Omnizip::Formats::Rar::Constants
      expect(constants::FILE_SPLIT_BEFORE).to eq(0x0001)
      expect(constants::FILE_SPLIT_AFTER).to eq(0x0002)
      expect(constants::FILE_ENCRYPTED).to eq(0x0004)
      expect(constants::FILE_DIRECTORY).to eq(0x00E0)
    end
  end

  describe "Models::RarEntry" do
    let(:entry) { Omnizip::Formats::Rar::Models::RarEntry.new }

    it "initializes with default values" do
      expect(entry.name).to be_nil
      expect(entry.size).to eq(0)
      expect(entry.compressed_size).to eq(0)
      expect(entry.is_dir).to eq(false)
    end

    it "checks if directory" do
      expect(entry.directory?).to eq(false)
      entry.is_dir = true
      expect(entry.directory?).to eq(true)
    end

    it "checks if file" do
      expect(entry.file?).to eq(true)
      entry.is_dir = true
      expect(entry.file?).to eq(false)
    end

    it "checks if encrypted" do
      expect(entry.encrypted?).to eq(false)
      entry.encrypted = true
      expect(entry.encrypted?).to eq(true)
    end

    it "checks if split across volumes" do
      expect(entry.split?).to eq(false)
      entry.split_before = true
      expect(entry.split?).to eq(true)
      entry.split_before = false
      entry.split_after = true
      expect(entry.split?).to eq(true)
    end
  end

  describe "Models::RarVolume" do
    let(:volume_path) { File.join(temp_dir, "test.part01.rar") }
    let(:volume) do
      Omnizip::Formats::Rar::Models::RarVolume.new(volume_path, 0)
    end

    it "initializes with path and number" do
      expect(volume.path).to eq(volume_path)
      expect(volume.volume_number).to eq(0)
    end

    it "checks if first volume" do
      expect(volume.first?).to eq(false)
      volume.is_first = true
      expect(volume.first?).to eq(true)
    end

    it "checks if last volume" do
      expect(volume.last?).to eq(false)
      volume.is_last = true
      expect(volume.last?).to eq(true)
    end

    it "checks if file exists" do
      expect(volume.exist?).to eq(false)
      FileUtils.touch(volume_path)
      expect(volume.exist?).to eq(true)
    end
  end

  describe "Models::RarArchive" do
    let(:archive_path) { File.join(temp_dir, "test.rar") }
    let(:archive) do
      Omnizip::Formats::Rar::Models::RarArchive.new(archive_path)
    end

    it "initializes with path" do
      expect(archive.path).to eq(archive_path)
      expect(archive.entries).to eq([])
      expect(archive.volumes).to eq([])
    end

    it "checks if multi-volume" do
      expect(archive.multi_volume?).to eq(false)
      archive.is_multi_volume = true
      expect(archive.multi_volume?).to eq(true)
    end

    it "returns total volumes count" do
      expect(archive.total_volumes).to eq(0)
      archive.volumes = [double, double, double]
      expect(archive.total_volumes).to eq(3)
    end

    it "returns format version string" do
      archive.version = 4
      expect(archive.format_version).to eq("RAR4")
      archive.version = 5
      expect(archive.format_version).to eq("RAR5")
    end

    it "returns entry count" do
      expect(archive.entry_count).to eq(0)
      archive.entries = [double, double]
      expect(archive.entry_count).to eq(2)
    end
  end

  describe "VolumeManager" do
    context "with RAR5 naming" do
      let(:base_path) { File.join(temp_dir, "archive.part01.rar") }
      let(:manager) { Omnizip::Formats::Rar::VolumeManager.new(base_path) }

      before do
        FileUtils.touch(base_path)
      end

      it "detects single volume" do
        expect(manager.volume_count).to eq(1)
        expect(manager.multi_volume?).to eq(false)
      end

      it "detects multiple volumes" do
        FileUtils.touch(File.join(temp_dir, "archive.part02.rar"))
        FileUtils.touch(File.join(temp_dir, "archive.part03.rar"))
        manager = Omnizip::Formats::Rar::VolumeManager.new(base_path)

        expect(manager.volume_count).to eq(3)
        expect(manager.multi_volume?).to eq(true)
      end

      it "returns first volume" do
        first = manager.first_volume
        expect(first).not_to be_nil
        expect(first.first?).to eq(true)
      end

      it "returns last volume" do
        last = manager.last_volume
        expect(last).not_to be_nil
        expect(last.last?).to eq(true)
      end

      it "returns volume paths" do
        paths = manager.volume_paths
        expect(paths).to be_an(Array)
        expect(paths.size).to eq(1)
      end
    end

    context "with RAR4 naming" do
      let(:base_path) { File.join(temp_dir, "archive.rar") }
      let(:manager) { Omnizip::Formats::Rar::VolumeManager.new(base_path) }

      before do
        FileUtils.touch(base_path)
      end

      it "detects single RAR4 volume" do
        expect(manager.volume_count).to eq(1)
        expect(manager.multi_volume?).to eq(false)
      end

      it "validates volume sequence" do
        expect(manager.valid_sequence?).to eq(true)
      end
    end
  end

  describe "Header" do
    it "detects RAR4 vs RAR5 format" do
      header = Omnizip::Formats::Rar::Header.new
      expect(header.valid?).to eq(false)

      # Set version manually for testing format methods
      header.instance_variable_set(:@version, 4)
      expect(header.rar4?).to eq(true)
      expect(header.rar5?).to eq(false)

      header.instance_variable_set(:@version, 5)
      expect(header.rar5?).to eq(true)
      expect(header.rar4?).to eq(false)
    end

    it "rejects invalid signature" do
      io = StringIO.new("INVALID#{"\x00" * 100}")
      header = Omnizip::Formats::Rar::Header.new
      expect { header.parse(io) }.to raise_error(/Invalid RAR signature/)
    end

    it "checks validity" do
      header = Omnizip::Formats::Rar::Header.new
      expect(header.valid?).to eq(false)
      header.instance_variable_set(:@version, 4)
      expect(header.valid?).to eq(true)
    end
  end

  describe "BlockParser" do
    let(:parser4) { Omnizip::Formats::Rar::BlockParser.new(4) }
    let(:parser5) { Omnizip::Formats::Rar::BlockParser.new(5) }

    it "initializes with version" do
      expect(parser4.version).to eq(4)
      expect(parser5.version).to eq(5)
    end

    it "skips blocks" do
      io = StringIO.new("A" * 100)
      parser4.skip_block(io, 10)
      expect(io.pos).to eq(10)
    end
  end

  describe "format registration" do
    it "registers RAR format" do
      expect(Omnizip::FormatRegistry.supported?(".rar")).to eq(true)
    end

    it "returns RAR reader class" do
      handler = Omnizip::FormatRegistry.get(".rar")
      expect(handler).to eq(Omnizip::Formats::Rar::Reader)
    end
  end
end
