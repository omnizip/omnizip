# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Omnizip::Formats::Zip::Writer do
  let(:output_path) { File.join(Dir.tmpdir, "test_#{Time.now.to_i}.zip") }
  let(:writer) { described_class.new(output_path) }

  after do
    FileUtils.rm_f(output_path)
  end

  describe "#initialize" do
    it "creates a new writer with file path" do
      expect(writer.file_path).to eq(output_path)
      expect(writer.entries).to be_empty
    end
  end

  describe "#add_data" do
    it "adds data to the archive" do
      writer.add_data("test.txt", "Hello, World!")
      expect(writer.entries.size).to eq(1)
      expect(writer.entries.first[:filename]).to eq("test.txt")
    end

    it "stores uncompressed data" do
      data = "Test data"
      writer.add_data("file.txt", data)
      entry = writer.entries.first
      expect(entry[:uncompressed_data]).to eq(data)
      expect(entry[:uncompressed_size]).to eq(data.bytesize)
    end
  end

  describe "#add_directory" do
    it "adds directory entry with trailing slash" do
      writer.add_directory("mydir")
      expect(writer.entries.size).to eq(1)
      expect(writer.entries.first[:filename]).to eq("mydir/")
      expect(writer.entries.first[:directory]).to be true
    end

    it "preserves trailing slash if provided" do
      writer.add_directory("mydir/")
      expect(writer.entries.first[:filename]).to eq("mydir/")
    end
  end

  describe "#write" do
    it "writes a valid ZIP archive" do
      writer.add_data("test.txt", "Hello, ZIP!")
      writer.write

      expect(File.exist?(output_path)).to be true
      expect(File.size(output_path)).to be > 0
    end

    it "writes archive with multiple entries" do
      writer.add_data("file1.txt", "Content 1")
      writer.add_data("file2.txt", "Content 2")
      writer.add_directory("subdir")
      writer.write

      expect(File.exist?(output_path)).to be true
    end

    it "uses specified compression method" do
      writer.add_data("test.txt", "Compress me!")
      writer.write(compression_method: Omnizip::Formats::Zip::Constants::COMPRESSION_DEFLATE)

      expect(File.exist?(output_path)).to be true
    end

    it "supports store (no compression) method" do
      writer.add_data("test.txt", "No compression")
      writer.write(compression_method: Omnizip::Formats::Zip::Constants::COMPRESSION_STORE)

      expect(File.exist?(output_path)).to be true
    end
  end

  describe "#write integration" do
    it "creates archive readable by Reader" do
      data = "Test content for round-trip"
      writer.add_data("roundtrip.txt", data)
      writer.write

      reader = Omnizip::Formats::Zip::Reader.new(output_path)
      reader.read

      expect(reader.entries.size).to eq(1)
      expect(reader.entries.first.filename).to eq("roundtrip.txt")
    end
  end
end
