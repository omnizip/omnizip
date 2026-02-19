# frozen_string_literal: true

require "spec_helper"
require "omnizip/format_detector"
require "tempfile"

RSpec.describe Omnizip::FormatDetector do
  describe ".detect" do
    it "detects XZ format" do
      # Create a minimal XZ file (just header)
      xz_data = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00].pack("C*")
      Tempfile.create(["test", ".xz"]) do |f|
        f.binmode
        f.write(xz_data)
        f.close

        expect(described_class.detect(f.path)).to eq(:xz)
      end
    end

    it "detects 7-Zip format" do
      # Create a minimal 7z file (just header)
      seven_zip_data = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C].pack("C*")
      Tempfile.create(["test", ".7z"]) do |f|
        f.binmode
        f.write(seven_zip_data)
        f.close

        expect(described_class.detect(f.path)).to eq(:seven_zip)
      end
    end

    it "detects RAR5 format" do
      rar5_data = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00].pack("C*")
      Tempfile.create(["test", ".rar"]) do |f|
        f.binmode
        f.write(rar5_data)
        f.close

        expect(described_class.detect(f.path)).to eq(:rar5)
      end
    end

    it "detects RAR4 format" do
      rar4_data = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00].pack("C*")
      Tempfile.create(["test", ".rar"]) do |f|
        f.binmode
        f.write(rar4_data)
        f.close

        expect(described_class.detect(f.path)).to eq(:rar4)
      end
    end

    it "detects ZIP format" do
      zip_data = [0x50, 0x4B, 0x03, 0x04].pack("C*")
      Tempfile.create(["test", ".zip"]) do |f|
        f.binmode
        f.write(zip_data)
        f.close

        expect(described_class.detect(f.path)).to eq(:zip)
      end
    end

    it "detects GZIP format" do
      gzip_data = [0x1F, 0x8B].pack("C*")
      Tempfile.create(["test", ".gz"]) do |f|
        f.binmode
        f.write(gzip_data)
        f.close

        expect(described_class.detect(f.path)).to eq(:gzip)
      end
    end

    it "detects BZIP2 format" do
      bzip2_data = [0x42, 0x5A].pack("C*")
      Tempfile.create(["test", ".bz2"]) do |f|
        f.binmode
        f.write(bzip2_data)
        f.close

        expect(described_class.detect(f.path)).to eq(:bzip2)
      end
    end

    it "returns nil for unknown format" do
      unknown_data = [0x00, 0x01, 0x02, 0x03].pack("C*")
      Tempfile.create(["test", ".bin"]) do |f|
        f.binmode
        f.write(unknown_data)
        f.close

        expect(described_class.detect(f.path)).to be_nil
      end
    end

    it "returns nil for non-existent file" do
      expect(described_class.detect("/non/existent/file.bin")).to be_nil
    end
  end

  describe ".xz?" do
    it "returns true for XZ format" do
      xz_data = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00].pack("C*")
      Tempfile.create(["test", ".xz"]) do |f|
        f.binmode
        f.write(xz_data)
        f.close

        expect(described_class.xz?(f.path)).to be true
      end
    end

    it "returns false for non-XZ format" do
      seven_zip_data = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C].pack("C*")
      Tempfile.create(["test", ".7z"]) do |f|
        f.binmode
        f.write(seven_zip_data)
        f.close

        expect(described_class.xz?(f.path)).to be false
      end
    end
  end

  describe ".seven_zip?" do
    it "returns true for 7-Zip format" do
      seven_zip_data = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C].pack("C*")
      Tempfile.create(["test", ".7z"]) do |f|
        f.binmode
        f.write(seven_zip_data)
        f.close

        expect(described_class.seven_zip?(f.path)).to be true
      end
    end

    it "returns false for non-7-Zip format" do
      xz_data = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00].pack("C*")
      Tempfile.create(["test", ".xz"]) do |f|
        f.binmode
        f.write(xz_data)
        f.close

        expect(described_class.seven_zip?(f.path)).to be false
      end
    end
  end

  describe ".reader_for" do
    it "returns XZ reader for XZ format" do
      xz_data = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00].pack("C*")
      Tempfile.create(["test", ".xz"]) do |f|
        f.binmode
        f.write(xz_data)
        f.close

        reader = described_class.reader_for(f.path)
        expect(reader).to eq(Omnizip::Formats::Xz)
      end
    end

    it "returns 7-Zip reader for 7-Zip format" do
      seven_zip_data = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C].pack("C*")
      Tempfile.create(["test", ".7z"]) do |f|
        f.binmode
        f.write(seven_zip_data)
        f.close

        reader = described_class.reader_for(f.path)
        expect(reader).to eq(Omnizip::Formats::SevenZip::Reader)
      end
    end

    it "returns nil for unknown format" do
      unknown_data = [0x00, 0x01, 0x02, 0x03].pack("C*")
      Tempfile.create(["test", ".bin"]) do |f|
        f.binmode
        f.write(unknown_data)
        f.close

        expect(described_class.reader_for(f.path)).to be_nil
      end
    end
  end

  describe "with reference files" do
    it "detects XZ reference files correctly" do
      xz_files = Dir.glob("spec/fixtures/xz_utils/reference/good-*.xz")
      skip "No XZ reference files found" if xz_files.empty?

      xz_files.first(5).each do |file|
        expect(described_class.detect(file)).to eq(:xz)
      end
    end

    it "detects 7-Zip reference files correctly" do
      seven_zip_files = Dir.glob("spec/fixtures/seven_zip/reference/*.7z")
      skip "No 7-Zip reference files found" if seven_zip_files.empty?

      seven_zip_files.first(5).each do |file|
        expect(described_class.detect(file)).to eq(:seven_zip)
      end
    end
  end
end
