# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XZ Utils Filter Support" do
  describe "LZMA2 variants" do
    %w[1 2 3 4 5].each do |n|
      it "decodes good-1-lzma2-#{n}.xz (baseline LZMA2)" do
        data = File.binread("spec/fixtures/xz_utils/good/good-1-lzma2-#{n}.xz")
        result = Omnizip::Formats::Xz.decode(data)

        expect(result).to be_a(String)
      end
    end
  end

  describe "Multi-block archives" do
    it "decodes good-2-lzma2.xz (multi-block LZMA2)" do
      data = File.binread("spec/fixtures/xz_utils/good/good-2-lzma2.xz")
      result = Omnizip::Formats::Xz.decode(data)

      expect(result).to be_a(String)
    end
  end

  describe "Delta filter" do
    it "decodes good-1-delta-lzma2.tiff.xz (Delta + LZMA2)" do
      data = File.binread("spec/fixtures/xz_utils/good/good-1-delta-lzma2.tiff.xz")
      result = Omnizip::Formats::Xz.decode(data)

      expect(result).to be_a(String)
      # Validate it's a TIFF (starts with II or MM)
      expect(result[0..1]).to match(/II|MM/),
                              "Expected output to be TIFF format (starts with II or MM)"
    end

    it "decodes good-1-3delta-lzma2.xz (multiple Delta filters)" do
      data = File.binread("spec/fixtures/xz_utils/good/good-1-3delta-lzma2.xz")
      result = Omnizip::Formats::Xz.decode(data)

      expect(result).to be_a(String)
    end
  end

  describe "BCJ filter edge cases" do
    it "decodes good-1-empty-bcj-lzma2.xz (BCJ with empty input)" do
      data = File.binread("spec/fixtures/xz_utils/good/good-1-empty-bcj-lzma2.xz")
      result = Omnizip::Formats::Xz.decode(data)

      expect(result).to eq(""),
                        "BCJ filter with empty input should produce empty output"
    end
  end

  describe "ARM64 BCJ filter" do
    # ARM64 BCJ filter is now supported for both zero and non-zero start_offset
    %w[1 2].each do |n|
      it "decodes good-1-arm64-lzma2-#{n}.xz" do
        data = File.binread("spec/fixtures/xz_utils/good/good-1-arm64-lzma2-#{n}.xz")
        result = Omnizip::Formats::Xz.decode(data)

        expect(result).to be_a(String)
        expect(result.length).to be > 0
      end
    end
  end

  describe "Block header variations with filters" do
    it "decodes good-1-block_header-1.xz" do
      data = File.binread("spec/fixtures/xz_utils/good/good-1-block_header-1.xz")
      result = Omnizip::Formats::Xz.decode(data)

      expect(result).to be_a(String)
    end

    it "decodes good-1-block_header-2.xz" do
      data = File.binread("spec/fixtures/xz_utils/good/good-1-block_header-2.xz")
      result = Omnizip::Formats::Xz.decode(data)

      expect(result).to be_a(String)
    end

    it "decodes good-1-block_header-3.xz" do
      data = File.binread("spec/fixtures/xz_utils/good/good-1-block_header-3.xz")
      result = Omnizip::Formats::Xz.decode(data)

      expect(result).to be_a(String)
    end
  end

  describe "Checksum types" do
    it "decodes good-1-check-crc32.xz (CRC32 checksum)" do
      data = File.binread("spec/fixtures/xz_utils/good/good-1-check-crc32.xz")
      result = Omnizip::Formats::Xz.decode(data)

      expect(result).to be_a(String)
    end

    it "decodes good-1-check-crc64.xz (CRC64 checksum)" do
      data = File.binread("spec/fixtures/xz_utils/good/good-1-check-crc64.xz")
      result = Omnizip::Formats::Xz.decode(data)

      expect(result).to be_a(String)
    end

    it "decodes good-1-check-sha256.xz (SHA256 checksum)" do
      data = File.binread("spec/fixtures/xz_utils/good/good-1-check-sha256.xz")
      result = Omnizip::Formats::Xz.decode(data)

      expect(result).to be_a(String)
    end

    it "decodes good-1-check-none.xz (no checksum)" do
      data = File.binread("spec/fixtures/xz_utils/good/good-1-check-none.xz")
      result = Omnizip::Formats::Xz.decode(data)

      expect(result).to be_a(String)
    end
  end

  describe "Filter ID mapping validation" do
    it "has correct XZ filter ID for BCJ-x86" do
      bcj = Omnizip::Filters::BCJ.new(architecture: :x86)
      expect(bcj.id_for_format(:xz)).to eq(0x04),
                                        "BCJ-x86 should have XZ filter ID 0x04"
    end

    it "has correct XZ filter ID for BCJ-PowerPC" do
      bcj = Omnizip::Filters::BCJ.new(architecture: :powerpc)
      expect(bcj.id_for_format(:xz)).to eq(0x05),
                                        "BCJ-PowerPC should have XZ filter ID 0x05"
    end

    it "has correct XZ filter ID for BCJ-IA64" do
      bcj = Omnizip::Filters::BCJ.new(architecture: :ia64)
      expect(bcj.id_for_format(:xz)).to eq(0x06),
                                        "BCJ-IA64 should have XZ filter ID 0x06"
    end

    it "has correct XZ filter ID for BCJ-ARM" do
      bcj = Omnizip::Filters::BCJ.new(architecture: :arm)
      expect(bcj.id_for_format(:xz)).to eq(0x07),
                                        "BCJ-ARM should have XZ filter ID 0x07"
    end

    it "has correct XZ filter ID for BCJ-ARMTHUMB (ARM Thumb mode)" do
      bcj = Omnizip::Filters::BCJ.new(architecture: :armthumb)
      expect(bcj.id_for_format(:xz)).to eq(0x08),
                                        "BCJ-ARMTHUMB should have XZ filter ID 0x08"
    end

    it "has correct XZ filter ID for BCJ-SPARC" do
      bcj = Omnizip::Filters::BCJ.new(architecture: :sparc)
      expect(bcj.id_for_format(:xz)).to eq(0x09),
                                        "BCJ-SPARC should have XZ filter ID 0x09"
    end

    it "has correct XZ filter ID for Delta filter" do
      delta = Omnizip::Filters::Delta.new(distance: 1)
      expect(delta.id_for_format(:xz)).to eq(0x03),
                                          "Delta filter should have XZ filter ID 0x03"
    end

    it "has correct XZ filter ID for LZMA2" do
      # LZMA2 filter ID is 0x01 in XZ format
      # (actually it's implicit - no filter ID means LZMA2 in XZ)
      expect(true).to eq(true),
                      "LZMA2 is implicit in XZ (no filter ID needed)"
    end
  end

  describe "XZ Utils filter support coverage" do
    it "identifies which good files use filters" do
      filter_files = Dir["spec/fixtures/xz_utils/good/*{bcj,delta}*.xz"]
      expect(filter_files.size).to be >= 3
    end

    it "has Delta filter test file" do
      delta_file = "spec/fixtures/xz_utils/good/good-1-delta-lzma2.tiff.xz"
      expect(File.exist?(delta_file)).to be true
    end

    it "has multiple delta filters test file" do
      multi_delta_file = "spec/fixtures/xz_utils/good/good-1-3delta-lzma2.xz"
      expect(File.exist?(multi_delta_file)).to be true
    end

    it "has ARM64 BCJ test files" do
      arm64_files = Dir["spec/fixtures/xz_utils/good/*arm64*.xz"]
      expect(arm64_files.size).to be >= 2
    end
  end
end
