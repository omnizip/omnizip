# frozen_string_literal: true

require "spec_helper"
require "omnizip/formats/xz"
require "fileutils"

RSpec.describe "XZ Utils Reference Files" do
  REFERENCE_DIR = File.expand_path("../../../fixtures/xz_utils/reference",
                                   __dir__)

  describe "good LZMA2 files" do
    good_lzma2_files = Dir.glob(File.join(REFERENCE_DIR, "good-*lzma2*.xz"))

    good_lzma2_files.each do |file_path|
      it "decompresses #{File.basename(file_path)}" do
        expect do
          data = Omnizip::Formats::Xz.decompress(file_path)
          expect(data).to be_a(String)
        end.not_to raise_error
      end
    end
  end

  describe "good LZMA_Alone files" do
    good_lz_files = Dir.glob(File.join(REFERENCE_DIR, "good-*.lz"))

    good_lz_files.each do |file_path|
      it "decompresses #{File.basename(file_path)}" do
        data = Omnizip::Formats::Lzip.decompress(file_path)
        expect(data).to be_a(String)
      end
    end
  end

  describe "good XZ files with various filters" do
    good_xz_files = Dir.glob(File.join(REFERENCE_DIR, "good-1-*.xz"))

    good_xz_files.each do |file_path|
      basename = File.basename(file_path)
      next if basename.include?("lzma2") # Already tested above

      it "decompresses #{basename}" do
        expect do
          data = Omnizip::Formats::Xz.decompress(file_path)
          expect(data).to be_a(String)
        end.not_to raise_error
      end
    end
  end

  describe "bad files (error handling)" do
    bad_files = Dir.glob(File.join(REFERENCE_DIR, "bad-*.xz"))

    bad_files.each do |file_path|
      it "rejects invalid file #{File.basename(file_path)}" do
        expect do
          Omnizip::Formats::Xz.decompress(file_path)
        end.to raise_error(Omnizip::Error)
      end
    end
  end
end
