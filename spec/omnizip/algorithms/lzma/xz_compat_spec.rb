# frozen_string_literal: true

require "spec_helper"
require "open3"
require "tempfile"
require "stringio"

# LZMA Cross-Implementation Compatibility Tests
#
# This file tests compatibility between different LZMA implementations:
# - 7-Zip SDK (implementations/seven_zip/lzma/)
# - XZ Utils (algorithms/lzma/xz_*.rb, xz_utils_decoder.rb)
# - xz command line tool
#
# IMPORTANT: While 7-Zip SDK and XZ Utils are different implementations,
# they both produce/consume standard LZMA format. Cross-compatibility tests
# verify that our implementations produce standard-compliant output.
RSpec.describe "LZMA Cross-Implementation Compatibility", :integration do
  # Skip if xz command not available
  before(:all) do
    @xz_available = system("which xz > /dev/null 2>&1")
    skip "xz command not available" unless @xz_available
  end

  # -------------------------------------------------------------------------
  # 7-Zip SDK Encoder → xz command (external compatibility)
  # -------------------------------------------------------------------------
  describe "7-Zip SDK encoder → xz command" do
    let(:test_data) { "Hello, World!" }
    let(:tempfile) { Tempfile.new(["omnizip_sdk_test", ".lzma"]) }

    after { tempfile.unlink }

    it "produces files decodable by xz" do
      require "omnizip/implementations/seven_zip/lzma/encoder"
      File.open(tempfile.path, "wb") do |f|
        encoder = Omnizip::Implementations::SevenZip::LZMA::Encoder.new(f)
        encoder.encode_stream(test_data)
      end

      decoded, status = Open3.capture2("xz", "-dc", tempfile.path, err: "/dev/null")

      expect(status.success?).to be(true), "xz failed to decode: #{status}"
      expect(decoded).to eq(test_data)
    end

    it "creates valid LZMA header" do
      require "omnizip/implementations/seven_zip/lzma/encoder"
      File.open(tempfile.path, "wb") do |f|
        encoder = Omnizip::Implementations::SevenZip::LZMA::Encoder.new(f, lc: 3, lp: 0, pb: 2)
        encoder.encode_stream(test_data)
      end

      header = File.binread(tempfile.path, 13)

      # Property byte: (lc + lp*9 + pb*45) = 3 + 0*9 + 2*45 = 93 = 0x5D
      expect(header[0].ord).to eq(0x5D)

      # Dictionary size (bytes 1-4, little-endian)
      dict_size = header[1..4].bytes.each_with_index.sum { |b, i| b << (i * 8) }
      expect(dict_size).to eq(65536) # Default 64KB

      # Uncompressed size (bytes 5-12, should be 0xFF for unknown)
      expect(header[5..12].bytes).to all(eq(0xFF))
    end
  end

  # -------------------------------------------------------------------------
  # xz command → XZ Utils Decoder (external compatibility)
  # -------------------------------------------------------------------------
  describe "xz command → XZ Utils decoder" do
    let(:test_data) { "Hello, World!" }
    let(:input_file) { Tempfile.new(["xz_input", ".txt"]) }

    after { input_file.unlink }

    it "decodes files created by xz" do
      require "omnizip/algorithms/lzma/xz_utils_decoder"

      File.write(input_file.path, test_data)
      system("xz", "-z", "-k", "--lzma1", "--format=lzma", input_file.path,
             out: "/dev/null", err: "/dev/null")

      lzma_file = "#{input_file.path}.lzma"
      expect(File.exist?(lzma_file)).to be true

      decoded = File.open(lzma_file, "rb") do |f|
        decoder = Omnizip::Algorithms::XzUtilsDecoder.new(f)
        decoder.decode_stream
      end

      expect(decoded).to eq(test_data)
      FileUtils.rm_f(lzma_file)
    end

    it "handles xz-encoded files with rep matches" do
      require "omnizip/algorithms/lzma/xz_utils_decoder"

      complex_data = "abc" * 100

      File.write(input_file.path, complex_data)
      system("xz", "-z", "-k", "--lzma1", "--format=lzma", input_file.path,
             out: "/dev/null", err: "/dev/null")

      lzma_file = "#{input_file.path}.lzma"

      decoded = File.open(lzma_file, "rb") do |f|
        decoder = Omnizip::Algorithms::XzUtilsDecoder.new(f)
        decoder.decode_stream
      end

      expect(decoded).to eq(complex_data)
      FileUtils.rm_f(lzma_file)
    end
  end

  # -------------------------------------------------------------------------
  # 7-Zip SDK Encoder → XZ Utils Decoder (cross-implementation compatibility)
  # This tests that SDK encoder produces standard LZMA format that XZ Utils can decode
  # -------------------------------------------------------------------------
  describe "7-Zip SDK encoder → XZ Utils decoder" do
    shared_examples "sdk to xz cross-compatibility" do |description, data_generator|
      it "handles #{description}" do
        require "omnizip/implementations/seven_zip/lzma/encoder"
        require "omnizip/algorithms/lzma/xz_utils_decoder"

        data = data_generator.call

        # Encode with SDK encoder
        encoded = StringIO.new
        encoder = Omnizip::Implementations::SevenZip::LZMA::Encoder.new(encoded)
        encoder.encode_stream(data)
        compressed = encoded.string

        # Decode with XZ Utils decoder
        decoded = StringIO.new(compressed)
        decoder = Omnizip::Algorithms::XzUtilsDecoder.new(decoded)
        result = decoder.decode_stream

        # Force binary encoding for comparison
        data = data.dup.force_encoding(Encoding::BINARY)
        result = result.force_encoding(Encoding::BINARY)

        expect(result).to eq(data)
        expect(result.bytesize).to eq(data.bytesize)
      end
    end

    include_examples "sdk to xz cross-compatibility", "simple text", -> { "Hello, World!" }
    include_examples "sdk to xz cross-compatibility", "repetitive data", -> { "a" * 1000 }
    include_examples "sdk to xz cross-compatibility", "binary data", -> { (0..255).to_a.pack("C*") * 4 }
    include_examples "sdk to xz cross-compatibility", "empty string", -> { "" }
    include_examples "sdk to xz cross-compatibility", "single byte", -> { "x" }
    include_examples "sdk to xz cross-compatibility", "mixed content", -> { "Hello\x00World\xFF\x01\x02" }
  end

  # -------------------------------------------------------------------------
  # 7-Zip SDK Encoder → 7-Zip SDK Decoder (internal round-trip)
  # -------------------------------------------------------------------------
  describe "7-Zip SDK round-trip (encoder → decoder)" do
    shared_examples "sdk round-trip" do |description, data_generator|
      it "handles #{description}" do
        require "omnizip/implementations/seven_zip/lzma/encoder"
        require "omnizip/implementations/seven_zip/lzma/decoder"

        data = data_generator.call

        # Encode with SDK encoder
        encoded = StringIO.new
        encoder = Omnizip::Implementations::SevenZip::LZMA::Encoder.new(encoded)
        encoder.encode_stream(data)
        compressed = encoded.string

        # Decode with SDK decoder
        decoded = StringIO.new(compressed)
        decoder = Omnizip::Implementations::SevenZip::LZMA::Decoder.new(decoded)
        result = decoder.decode_stream

        data = data.dup.force_encoding(Encoding::BINARY)
        result = result.force_encoding(Encoding::BINARY)

        expect(result).to eq(data)
        expect(result.bytesize).to eq(data.bytesize)
      end
    end

    include_examples "sdk round-trip", "simple text", -> { "Hello, World!" }
    include_examples "sdk round-trip", "repetitive data", -> { "a" * 1000 }
    include_examples "sdk round-trip", "binary data", -> { (0..255).to_a.pack("C*") * 4 }
    include_examples "sdk round-trip", "empty string", -> { "" }
    include_examples "sdk round-trip", "single byte", -> { "x" }
  end

  # -------------------------------------------------------------------------
  # Format structure validation
  # -------------------------------------------------------------------------
  describe "LZMA format structure" do
    it "matches standard LZMA header format" do
      require "omnizip/implementations/seven_zip/lzma/encoder"

      data = "test"
      output = StringIO.new

      encoder = Omnizip::Implementations::SevenZip::LZMA::Encoder.new(output,
                                                                      lc: 3, lp: 0, pb: 2, dict_size: 1 << 16)
      encoder.encode_stream(data)

      compressed = output.string

      # Verify header structure (13 bytes)
      expect(compressed.bytesize).to be >= 13

      # Property byte
      props = compressed[0].ord
      lc = props % 9
      remainder = props / 9
      lp = remainder % 5
      pb = remainder / 5

      expect(lc).to eq(3)
      expect(lp).to eq(0)
      expect(pb).to eq(2)

      # Dictionary size
      dict_size = compressed[1..4].bytes.each_with_index.sum { |b, i| b << (i * 8) }
      expect(dict_size).to eq(65536)

      # Uncompressed size (unknown size marker)
      size_bytes = compressed[5..12].bytes
      expect(size_bytes).to all(eq(0xFF))
    end
  end
end
