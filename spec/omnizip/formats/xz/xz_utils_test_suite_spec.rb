# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XZ Utils Compatibility Test Suite" do
  describe "good files (should decode successfully)" do
    # Support XZ, LZMA (.lzma), and LZMA Utils (.lz) formats
    good_files = Dir["spec/fixtures/xz_utils/good/*.{xz,lz,lzma}"]

    good_files.each do |file|
      filename = File.basename(file)

      it "decodes #{filename}" do
        data = File.binread(file)

        # Use appropriate decoder based on file extension
        result = if file.end_with?(".lzma")
                   Omnizip::Algorithms::LZMA::LzmaAloneDecoder.new(StringIO.new(data)).decode_stream
                 elsif file.end_with?(".lz")
                   require "omnizip/algorithms/lzma/lzip_decoder"
                   Omnizip::Algorithms::LZMA::LzipDecoder.new(StringIO.new(data)).decode_stream
                 else
                   Omnizip::Formats::Xz.decode(data)
                 end

        expect(result).to be_a(String),
                          "Expected #{filename} to decode to a String"
      end
    end
  end

  describe "bad files (should raise errors)" do
    # Support XZ, LZMA (.lzma), and LZMA Utils (.lz) formats
    bad_files = Dir["spec/fixtures/xz_utils/bad/*.{xz,lz,lzma}"]

    bad_files.each do |file|
      filename = File.basename(file)

      it "rejects #{filename}" do
        data = File.binread(file)

        # Use appropriate decoder based on file extension
        expect do
          if file.end_with?(".lzma")
            Omnizip::Algorithms::LZMA::LzmaAloneDecoder.new(StringIO.new(data)).decode_stream
          elsif file.end_with?(".lz")
            require "omnizip/algorithms/lzma/lzip_decoder"
            Omnizip::Algorithms::LZMA::LzipDecoder.new(StringIO.new(data)).decode_stream
          else
            Omnizip::Formats::Xz.decode(data)
          end
        end.to raise_error(Omnizip::Error),
               "Expected #{filename} to raise Omnizip::Error"
      end
    end
  end

  describe "unsupported files (should fail gracefully)" do
    # Support XZ and LZ formats
    unsupported_files = Dir["spec/fixtures/xz_utils/unsupported/*.{xz,lz}"]

    unsupported_files.each do |file|
      filename = File.basename(file)

      it "handles #{filename} gracefuly" do
        data = File.binread(file)

        # Should either decode (if we support the feature) or raise a clear error
        begin
          # Use appropriate decoder based on file extension
          result = if file.end_with?(".lz")
                     require "omnizip/algorithms/lzma/lzip_decoder"
                     Omnizip::Algorithms::LZMA::LzipDecoder.new(StringIO.new(data)).decode_stream
                   else
                     Omnizip::Formats::Xz.decode(data)
                   end
          expect(result).to be_a(String),
                            "Expected #{filename} to decode to a String if supported"
        rescue Omnizip::Error => e
          # Error message should be clear about what's not supported
          expect(e.message).to match(/unsupported|not (implemented|supported)/i),
                               "Expected #{filename} error message to mention unsupported feature, got: #{e.message}"
        end
      end
    end
  end

  describe "good file validation" do
    it "has the expected number of good test files" do
      files = Dir["spec/fixtures/xz_utils/good/*.{xz,lz,lzma}"]
      expect(files.size).to eq(33),
                            "Expected 33 good test files, got #{files.size}"
    end

    it "includes LZMA2 test files" do
      lzma2_files = Dir["spec/fixtures/xz_utils/good/good-1-lzma2-*.xz"]
      expect(lzma2_files.size).to be >= 5,
                                  "Expected at least 5 LZMA2 test files, got #{lzma2_files.size}"
    end

    it "includes BCJ filter test files" do
      bcj_files = Dir["spec/fixtures/xz_utils/good/*bcj*.xz"]
      expect(bcj_files.size).to be >= 1,
                                "Expected at least 1 BCJ test file, got #{bcj_files.size}"
    end

    it "includes Delta filter test files" do
      delta_files = Dir["spec/fixtures/xz_utils/good/*delta*.xz"]
      expect(delta_files.size).to be >= 2,
                                  "Expected at least 2 Delta test files, got #{delta_files.size}"
    end
  end

  describe "bad file validation" do
    it "has the expected number of bad test files" do
      files = Dir["spec/fixtures/xz_utils/bad/*.{xz,lz,lzma}"]
      expect(files.size).to eq(56),
                            "Expected 56 bad test files, got #{files.size}"
    end

    it "includes stream-level error tests" do
      stream_errors = Dir["spec/fixtures/xz_utils/bad/bad-0-*"]
      expect(stream_errors.size).to be >= 5,
                                    "Expected at least 5 stream-level error test files, got #{stream_errors.size}"
    end

    it "includes block-level error tests" do
      block_errors = Dir["spec/fixtures/xz_utils/bad/bad-1-*"]
      expect(block_errors.size).to be >= 20,
                                   "Expected at least 20 block-level error test files, got #{block_errors.size}"
    end

    it "includes LZMA2 error tests" do
      lzma2_errors = Dir["spec/fixtures/xz_utils/bad/bad-1-lzma2-*.xz"]
      expect(lzma2_errors.size).to be >= 10,
                                   "Expected at least 10 LZMA2 error test files, got #{lzma2_errors.size}"
    end
  end

  describe "unsupported file validation" do
    it "has the expected number of unsupported test files" do
      files = Dir["spec/fixtures/xz_utils/unsupported/*.{xz,lz}"]
      expect(files.size).to eq(6),
                            "Expected 6 unsupported test files, got #{files.size}"
    end
  end

  describe "known good files with specific validation" do
    it "decodes good-1-lzma2-1.xz successfully" do
      data = File.binread("spec/fixtures/xz_utils/good/good-1-lzma2-1.xz")
      result = Omnizip::Formats::Xz.decode(data)

      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end

    it "decodes good-2-lzma2.xz (multi-block) successfully" do
      data = File.binread("spec/fixtures/xz_utils/good/good-2-lzma2.xz")
      result = Omnizip::Formats::Xz.decode(data)

      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end

    it "decodes good-1-empty-bcj-lzma2.xz to empty string" do
      data = File.binread("spec/fixtures/xz_utils/good/good-1-empty-bcj-lzma2.xz")
      result = Omnizip::Formats::Xz.decode(data)

      expect(result).to eq("")
    end
  end

  describe "known bad files with specific validation" do
    it "rejects bad-0-header_magic.xz with appropriate error" do
      data = File.binread("spec/fixtures/xz_utils/bad/bad-0-header_magic.xz")

      expect { Omnizip::Formats::Xz.decode(data) }.to raise_error(Omnizip::Error)
    end

    it "rejects bad-0-footer_magic.xz with appropriate error" do
      data = File.binread("spec/fixtures/xz_utils/bad/bad-0-footer_magic.xz")

      expect { Omnizip::Formats::Xz.decode(data) }.to raise_error(Omnizip::Error)
    end

    it "rejects bad-1-check-crc32.xz (corrupted checksum)" do
      data = File.binread("spec/fixtures/xz_utils/bad/bad-1-check-crc32.xz")

      expect { Omnizip::Formats::Xz.decode(data) }.to raise_error(Omnizip::Error)
    end
  end

  describe "total test coverage" do
    it "has 95 total test files from XZ Utils" do
      good_files = Dir["spec/fixtures/xz_utils/good/*.{xz,lz,lzma}"].size
      bad_files = Dir["spec/fixtures/xz_utils/bad/*.{xz,lz,lzma}"].size
      unsupported_files = Dir["spec/fixtures/xz_utils/unsupported/*.{xz,lz}"].size
      total = good_files + bad_files + unsupported_files

      expect(total).to eq(95),
                       "Expected 95 total test files (33 good + 56 bad + 6 unsupported), got #{total}"
    end
  end
end
