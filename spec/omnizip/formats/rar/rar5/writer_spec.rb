# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/rar5/writer"

RSpec.describe Omnizip::Formats::Rar::Rar5::Writer do
  let(:temp_file) { Tempfile.new(["test", ".rar"]) }
  let(:output_path) { temp_file.path }

  after do
    temp_file.close
    temp_file.unlink
  end

  describe "#initialize" do
    it "creates writer with path" do
      writer = described_class.new(output_path)
      expect(writer.path).to eq(output_path)
    end

    it "accepts options" do
      writer_with_opts = described_class.new(output_path, compression: :best)
      expect(writer_with_opts.options[:compression]).to eq(:best)
      expect(writer_with_opts.options[:level]).to eq(3) # default level
    end
  end

  describe "#add_file" do
    let(:test_file) do
      file = Tempfile.new(["source", ".txt"])
      file.write("test content")
      file.close
      file
    end

    after do
      test_file.unlink
    end

    it "adds file to archive" do
      writer = described_class.new(output_path)
      writer.add_file(test_file.path)
      expect(writer.instance_variable_get(:@files).size).to eq(1)
    end

    it "accepts custom archive path" do
      writer = described_class.new(output_path)
      writer.add_file(test_file.path, "custom/path.txt")
      files = writer.instance_variable_get(:@files)
      expect(files.first[:archive]).to eq("custom/path.txt")
    end

    it "raises error for non-existent file" do
      writer = described_class.new(output_path)
      expect do
        writer.add_file("nonexistent.txt")
      end.to raise_error(ArgumentError)
    end
  end

  describe "#write" do
    it "creates RAR5 archive file" do
      writer = described_class.new(output_path)
      writer.write
      expect(File.exist?(output_path)).to be true
    end

    it "writes RAR5 signature" do
      writer = described_class.new(output_path)
      writer.write

      File.open(output_path, "rb") do |f|
        signature = f.read(8)
        expect(signature).to eq([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01,
                                 0x00].pack("C*"))
      end
    end

    it "creates valid empty archive" do
      writer = described_class.new(output_path)
      writer.write

      content = File.binread(output_path)
      expect(content.size).to be > 8
    end

    it "returns archive path" do
      writer = described_class.new(output_path)
      result = writer.write
      expect(result).to eq(output_path)
    end
  end

  describe "#write with files" do
    let(:test_file) do
      file = Tempfile.new(["source", ".txt"])
      file.write("test content")
      file.close
      file
    end

    after do
      test_file.unlink
    end

    it "creates archive with file content" do
      writer = described_class.new(output_path)
      writer.add_file(test_file.path)
      writer.write

      expect(File.exist?(output_path)).to be true
      expect(File.size(output_path)).to be > 8
    end

    it "includes file data in archive" do
      writer = described_class.new(output_path)
      writer.add_file(test_file.path, "test.txt")
      writer.write

      content = File.binread(output_path)
      expect(content).to include("test content")
    end
  end
end
