# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require_relative "../../../../../../lib/omnizip/formats/rar/rar5/multi_volume/volume_writer"
require_relative "../../../../../../lib/omnizip/formats/rar/rar5/header"

RSpec.describe Omnizip::Formats::Rar::Rar5::MultiVolume::VolumeWriter do
  let(:temp_path) { File.join(Dir.tmpdir, "test_volume.part1.rar") }
  let(:writer) do
    described_class.new(temp_path, volume_number: 1, is_last: false)
  end

  after do
    FileUtils.rm_f(temp_path)
  end

  describe "#initialize" do
    it "initializes with path and volume number" do
      expect(writer.path).to eq(temp_path)
      expect(writer.volume_number).to eq(1)
      expect(writer.is_last).to be false
    end

    it "initializes last volume" do
      last_writer = described_class.new(temp_path, volume_number: 3,
                                                   is_last: true)

      expect(last_writer.is_last).to be true
    end
  end

  describe "#write" do
    it "opens and closes file automatically" do
      writer.write do |w|
        expect(w.io).not_to be_nil
      end

      expect(writer.io).to be_nil
    end

    it "creates the volume file" do
      writer.write { |_w| }

      expect(File.exist?(temp_path)).to be true
    end

    it "closes file even if block raises error" do
      expect do
        writer.write { raise "test error" }
      end.to raise_error("test error")

      expect(writer.io).to be_nil
    end
  end

  describe "#write_signature" do
    it "writes RAR5 signature" do
      writer.write(&:write_signature)

      data = File.binread(temp_path)
      signature = data[0, 8].unpack("C*")

      expect(signature).to eq([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00])
    end

    it "raises error if volume not open" do
      expect { writer.write_signature }.to raise_error(/not open/)
    end
  end

  describe "#write_main_header" do
    it "writes main header" do
      writer.write do |w|
        w.write_signature
        w.write_main_header
      end

      data = File.binread(temp_path)
      expect(data.bytesize).to be > 8 # More than just signature
    end

    it "raises error if volume not open" do
      expect { writer.write_main_header }.to raise_error(/not open/)
    end
  end

  describe "#write_end_header" do
    it "writes end header" do
      writer.write do |w|
        w.write_signature
        w.write_main_header
        w.write_end_header
      end

      expect(File.exist?(temp_path)).to be true
    end

    it "raises error if volume not open" do
      expect { writer.write_end_header }.to raise_error(/not open/)
    end
  end

  describe ".volume_filename" do
    it "generates part-style filename" do
      filename = described_class.volume_filename("archive.rar", 1,
                                                 naming: "part")

      expect(filename).to eq("archive.part1.rar")
    end

    it "generates part-style for subsequent volumes" do
      filename = described_class.volume_filename("archive.rar", 5,
                                                 naming: "part")

      expect(filename).to eq("archive.part5.rar")
    end

    it "generates volume-style filename" do
      filename = described_class.volume_filename("archive.rar", 1,
                                                 naming: "volume")

      expect(filename).to eq("archive.vol1.rar")
    end

    it "generates numeric-style for first volume" do
      filename = described_class.volume_filename("archive.rar", 1,
                                                 naming: "numeric")

      expect(filename).to eq("archive.rar")
    end

    it "generates numeric-style for subsequent volumes" do
      filename = described_class.volume_filename("archive.rar", 2,
                                                 naming: "numeric")

      expect(filename).to eq("archive.r00")
    end

    it "handles paths with directories" do
      filename = described_class.volume_filename("/tmp/backup/archive.rar", 2,
                                                 naming: "part")

      expect(filename).to eq("/tmp/backup/archive.part2.rar")
    end

    it "handles paths with no extension" do
      filename = described_class.volume_filename("archive", 1, naming: "part")

      expect(filename).to eq("archive.part1")
    end

    it "defaults to part naming" do
      filename = described_class.volume_filename("archive.rar", 3)

      expect(filename).to eq("archive.part3.rar")
    end
  end

  describe "integration: full volume write" do
    it "creates valid volume file" do
      # Create a simple file header
      file_header = Omnizip::Formats::Rar::Rar5::FileHeader.new(
        filename: "test.txt",
        file_size: 11,
        compressed_size: 11,
        compression_method: 0,
      )
      compressed_data = "Hello World"

      writer.write do |w|
        w.write_signature
        w.write_main_header
        w.write_file_data(file_header, compressed_data)
        w.write_end_header
      end

      # Verify file exists and has content
      expect(File.exist?(temp_path)).to be true
      expect(File.size(temp_path)).to be > 50 # Minimal RAR5 archive
    end
  end
end
