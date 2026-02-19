# frozen_string_literal: true

require "spec_helper"
require "omnizip/converter"
require "omnizip/zip/file"
require "tempfile"

RSpec.describe Omnizip::Converter do
  let(:test_zip) { Tempfile.new(["test", ".zip"]) }
  let(:test_7z) { Tempfile.new(["test", ".7z"]) }
  let(:output_zip) { Tempfile.new(["output", ".zip"]) }
  let(:output_7z) { Tempfile.new(["output", ".7z"]) }

  before do
    # Create test ZIP archive
    Omnizip::Zip::File.create(test_zip.path) do |zip|
      zip.add("file1.txt") { "content1" }
      zip.add("file2.txt") { "content2" }
      zip.add("dir/") # Directory
      zip.add("dir/file3.txt") { "content3" }
    end
  end

  after do
    [test_zip, test_7z, output_zip, output_7z].each do |f|
      f.close
      f.unlink if File.exist?(f.path)
    end
  end

  describe ".convert" do
    it "converts ZIP to 7z" do
      result = described_class.convert(test_zip.path, output_7z.path)

      expect(result).to be_a(Omnizip::Models::ConversionResult)
      expect(File.exist?(output_7z.path)).to be true
      expect(result.source_format).to eq(:zip)
      expect(result.target_format).to eq(:seven_zip)
      expect(result.entry_count).to be > 0
    end

    it "raises error for non-existent source" do
      expect do
        described_class.convert("nonexistent.zip", output_7z.path)
      end.to raise_error(Errno::ENOENT, /Source file not found/)
    end

    it "raises error for unsupported conversion" do
      expect do
        described_class.convert("file.unknown", "file.zip")
      end.to raise_error(ArgumentError, /No conversion strategy/)
    end

    it "accepts options hash" do
      result = described_class.convert(
        test_zip.path,
        output_7z.path,
        compression: :lzma2,
        compression_level: 9,
      )

      expect(result).to be_a(Omnizip::Models::ConversionResult)
    end
  end

  describe ".supported?" do
    it "returns true for supported conversions" do
      expect(described_class.supported?(test_zip.path, "output.7z")).to be true
    end

    it "returns false for unsupported conversions" do
      expect(described_class.supported?("file.rar", "output.zip")).to be false
    end
  end

  describe ".strategies" do
    it "returns available strategies" do
      strategies = described_class.strategies
      expect(strategies).to be_an(Array)
      expect(strategies).not_to be_empty
    end
  end

  describe Omnizip::Models::ConversionOptions do
    subject { described_class.new }

    it "has default values" do
      expect(subject.target_format).to eq(:seven_zip)
      expect(subject.compression_level).to eq(5)
      expect(subject.preserve_metadata).to be true
      expect(subject.solid).to be true
    end

    it "validates options" do
      expect { subject.validate }.not_to raise_error
    end

    it "rejects invalid formats" do
      subject.target_format = :invalid
      expect do
        subject.validate
      end.to raise_error(ArgumentError, /Invalid target format/)
    end

    it "rejects invalid compression levels" do
      subject.compression_level = 10
      expect do
        subject.validate
      end.to raise_error(ArgumentError, /Invalid compression level/)
    end

    it "converts to hash" do
      hash = subject.to_h
      expect(hash).to include(:target_format, :compression, :compression_level)
    end
  end

  describe Omnizip::Models::ConversionResult do
    let(:result) do
      described_class.new(
        source_path: "test.zip",
        target_path: "test.7z",
        source_format: :zip,
        target_format: :seven_zip,
        source_size: 1000,
        target_size: 800,
        duration: 1.5,
        entry_count: 3,
      )
    end

    it "calculates size reduction" do
      expect(result.size_reduction).to eq(20.0)
    end

    it "calculates size ratio" do
      expect(result.size_ratio).to eq(80.0)
    end

    it "checks if smaller" do
      expect(result.smaller?).to be true
    end

    it "checks if larger" do
      expect(result.larger?).to be false
    end

    it "calculates processing speed" do
      expect(result.processing_speed).to be > 0
    end

    it "converts to hash" do
      hash = result.to_h
      expect(hash).to include(:source_path, :target_path, :duration,
                              :entry_count)
    end

    it "formats as string" do
      str = result.to_s
      expect(str).to include("test.zip", "test.7z", "Saved 20%")
    end
  end

  describe Omnizip::Converter::ConversionRegistry do
    it "finds strategy for ZIP to 7z" do
      strategy = described_class.find_strategy("test.zip", "test.7z")
      expect(strategy).to eq(Omnizip::Converter::ZipToSevenZipStrategy)
    end

    it "returns nil for unsupported conversion" do
      strategy = described_class.find_strategy("test.rar", "test.zip")
      expect(strategy).to be_nil
    end

    it "checks if conversion is supported" do
      expect(described_class.supported?("test.zip", "test.7z")).to be true
      expect(described_class.supported?("test.rar", "test.zip")).to be false
    end
  end

  describe Omnizip::Converter::ZipToSevenZipStrategy do
    let(:options) { Omnizip::Models::ConversionOptions.new }
    subject { described_class.new(test_zip.path, output_7z.path, options) }

    it "identifies source and target formats" do
      expect(subject.source_format).to eq(:zip)
      expect(subject.target_format).to eq(:seven_zip)
    end

    it "checks if can convert" do
      expect(described_class.can_convert?("test.zip", "test.7z")).to be true
      expect(described_class.can_convert?("test.7z", "test.zip")).to be false
    end
  end

  describe Omnizip::Converter::SevenZipToZipStrategy do
    let(:options) { Omnizip::Models::ConversionOptions.new }
    subject { described_class.new("test.7z", output_zip.path, options) }

    it "identifies source and target formats" do
      expect(subject.source_format).to eq(:seven_zip)
      expect(subject.target_format).to eq(:zip)
    end

    it "checks if can convert" do
      expect(described_class.can_convert?("test.7z", "test.zip")).to be true
      expect(described_class.can_convert?("test.zip", "test.7z")).to be false
    end
  end
end
