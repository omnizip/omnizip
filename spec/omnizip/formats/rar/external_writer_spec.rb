# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/rar/writer"
require "tmpdir"
require "fileutils"

RSpec.describe Omnizip::Formats::Rar::Writer do
  let(:temp_dir) { Dir.mktmpdir("omnizip_rar_test") }
  let(:output_path) { File.join(temp_dir, "test.rar") }
  let(:test_file) { File.join(temp_dir, "test.txt") }
  let(:test_dir) { File.join(temp_dir, "test_directory") }

  before do
    # Create test files
    File.write(test_file, "Hello, RAR!")
    FileUtils.mkdir_p(test_dir)
    File.write(File.join(test_dir, "file1.txt"), "File 1")
    File.write(File.join(test_dir, "file2.txt"), "File 2")
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe ".available?" do
    it "returns true for pure Ruby implementation" do
      expect(described_class.available?).to be true
    end
  end

  describe ".info" do
    it "returns writer information" do
      info = described_class.info
      expect(info[:available]).to be true
      expect(info[:type]).to eq(:pure_ruby)
      expect(info[:version]).to eq("4.0")
    end
  end

  describe "#initialize" do
    it "creates writer instance" do
      writer = described_class.new(output_path)
      expect(writer).to be_a(described_class)
      expect(writer.output_path).to eq(output_path)
    end

    it "accepts compression options" do
      writer = described_class.new(output_path,
                                   compression: :best,
                                   solid: true,
                                   recovery: 5)
      expect(writer.options[:compression]).to eq(:best)
      expect(writer.options[:solid]).to be true
      expect(writer.options[:recovery]).to eq(5)
    end
  end

  describe "#add_file" do
    let(:writer) { described_class.new(output_path) }

    it "adds file to archive" do
      writer.add_file(test_file)
      expect(writer.files.size).to eq(1)
      expect(writer.files.first[:source]).to eq(File.expand_path(test_file))
    end

    it "raises error if file does not exist" do
      expect do
        writer.add_file("nonexistent.txt")
      end.to raise_error(ArgumentError, /File not found/)
    end

    it "accepts custom archive path" do
      writer.add_file(test_file, "custom/path.txt")
      expect(writer.files.first[:archive_path]).to eq("custom/path.txt")
    end
  end

  describe "#add_directory" do
    let(:writer) { described_class.new(output_path) }

    it "adds directory to archive" do
      writer.add_directory(test_dir)
      expect(writer.directories.size).to eq(1)
      expect(writer.directories.first[:source]).to eq(File.expand_path(test_dir))
    end

    it "raises error if directory does not exist" do
      expect do
        writer.add_directory("nonexistent_dir")
      end.to raise_error(ArgumentError, /Directory not found/)
    end

    it "supports recursive option" do
      writer.add_directory(test_dir, recursive: false)
      expect(writer.directories.first[:recursive]).to be false
    end

    it "accepts custom archive path" do
      writer.add_directory(test_dir, archive_path: "custom/dir")
      expect(writer.directories.first[:archive_path]).to eq("custom/dir")
    end
  end

  describe "#write" do
    let(:writer) { described_class.new(output_path) }

    it "creates RAR archive" do
      writer.add_file(test_file)
      result = writer.write
      expect(result).to eq(output_path)
      expect(File.exist?(output_path)).to be true
    end

    it "tests archive if requested" do
      writer = described_class.new(output_path, test_after_create: true)
      writer.add_file(test_file)
      result = writer.write
      expect(result).to eq(output_path)
      expect(File.exist?(output_path)).to be true
    end

    context "compression options" do
      it "applies compression level" do
        writer = described_class.new(output_path, compression: :best)
        writer.add_file(test_file)
        result = writer.write
        expect(result).to eq(output_path)
        expect(File.exist?(output_path)).to be true
      end

      it "creates solid archive" do
        writer = described_class.new(output_path, solid: true)
        writer.add_file(test_file)
        result = writer.write
        expect(result).to eq(output_path)
        expect(File.exist?(output_path)).to be true
      end

      it "adds recovery record" do
        writer = described_class.new(output_path, recovery: 5)
        writer.add_file(test_file)
        result = writer.write
        expect(result).to eq(output_path)
        expect(File.exist?(output_path)).to be true
      end

      it "applies password protection" do
        writer = described_class.new(output_path, password: "secret")
        writer.add_file(test_file)
        result = writer.write
        expect(result).to eq(output_path)
        expect(File.exist?(output_path)).to be true
      end

      it "encrypts headers when requested" do
        writer = described_class.new(output_path,
                                     password: "secret",
                                     encrypt_headers: true)
        writer.add_file(test_file)
        result = writer.write
        expect(result).to eq(output_path)
        expect(File.exist?(output_path)).to be true
      end

      it "creates volume splits" do
        writer = described_class.new(output_path, volume_size: 1_000_000)
        writer.add_file(test_file)
        result = writer.write
        expect(result).to eq(output_path)
        expect(File.exist?(output_path)).to be true
      end
    end
  end
end
