# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Omnizip::Implementations::SevenZip::LZMA::Encoder do
  describe "SDK encoding" do
    it "encodes simple text" do
      output = StringIO.new
      encoder = described_class.new(output, lc: 3, lp: 0, pb: 2,
                                            dict_size: 65536)

      data = "Hello, World!"
      encoder.encode_stream(data)

      # Should produce non-empty output
      expect(output.string.bytesize).to be > 0

      # Should have LZMA header (13 bytes)
      expect(output.string.bytesize).to be >= 13
    end

    it "produces smaller output for repetitive data" do
      output = StringIO.new
      encoder = described_class.new(output, lc: 3, lp: 0, pb: 2,
                                            dict_size: 65536)

      data = "A" * 1000
      encoder.encode_stream(data)

      # Should compress well (much less than 1000 + 13 header)
      expect(output.string.bytesize).to be < 200
    end

    it "writes correct LZMA header" do
      output = StringIO.new
      encoder = described_class.new(output, lc: 3, lp: 0, pb: 2,
                                            dict_size: 65536)

      data = "Test"
      encoder.encode_stream(data)

      output.rewind
      header = output.read(13)

      # Property byte: lc + lp*9 + pb*45 = 3 + 0*9 + 2*45 = 93
      expect(header[0].ord).to eq(93)

      # Dictionary size (4 bytes LE): 65536 = 0x00010000
      dict_bytes = header[1..4].bytes
      dict_size = dict_bytes[0] | (dict_bytes[1] << 8) | (dict_bytes[2] << 16) | (dict_bytes[3] << 24)
      expect(dict_size).to eq(65536)

      # Uncompressed size (8 bytes, all 0xFF for unknown size)
      size_bytes = header[5..12].bytes
      expect(size_bytes).to all(eq(0xFF))
    end

    it "handles empty input" do
      output = StringIO.new
      encoder = described_class.new(output)

      data = ""
      encoder.encode_stream(data)

      # Should still produce header + EOS marker
      expect(output.string.bytesize).to be >= 13
    end

    it "handles single byte input" do
      output = StringIO.new
      encoder = described_class.new(output)

      data = "A"
      encoder.encode_stream(data)

      expect(output.string.bytesize).to be > 13
    end

    it "respects configuration parameters" do
      # Test with different lc/lp/pb values
      output = StringIO.new
      encoder = described_class.new(output, lc: 2, lp: 1, pb: 1,
                                            dict_size: 32768)

      data = "Test data"
      encoder.encode_stream(data)

      output.rewind
      props = output.read(1).ord

      # Property byte: lc + lp*9 + pb*45 = 2 + 1*9 + 1*45 = 56
      expect(props).to eq(56)
    end

    it "validates parameters" do
      expect do
        described_class.new(StringIO.new, lc: 9)
      end.to raise_error(ArgumentError, /lc must be 0-8/)

      expect do
        described_class.new(StringIO.new, lp: 5)
      end.to raise_error(ArgumentError, /lp must be 0-4/)

      expect do
        described_class.new(StringIO.new, pb: 5)
      end.to raise_error(ArgumentError, /pb must be 0-4/)

      expect do
        described_class.new(StringIO.new, level: 10)
      end.to raise_error(ArgumentError, /level must be 0-9/)
    end
  end

  describe "integration with Encoder factory" do
    it "can be accessed via Encoder with sdk_compatible flag" do
      output = StringIO.new
      encoder = Omnizip::Algorithms::LZMA::Encoder.new(output,
                                                       sdk_compatible: true)

      data = "Test data"
      encoder.encode_stream(data)

      expect(output.string.bytesize).to be > 13
    end

    it "supports XZ Utils compatible mode" do
      sdk_output = StringIO.new
      xz_output = StringIO.new

      data = "Test data for comparison"

      # SDK mode (default)
      sdk_encoder = Omnizip::Algorithms::LZMA::Encoder.new(sdk_output,
                                                           sdk_compatible: true)
      sdk_encoder.encode_stream(data)

      # XZ Utils mode
      xz_encoder = Omnizip::Algorithms::LZMA::Encoder.new(xz_output,
                                                          xz_compatible: true)
      xz_encoder.encode_stream(data)

      # Both should produce output
      expect(sdk_output.string.bytesize).to be > 13
      expect(xz_output.string.bytesize).to be > 13
    end
  end

  describe "match encoding" do
    it "encodes matches for repetitive patterns" do
      output = StringIO.new
      encoder = described_class.new(output)

      # Data with clear repetition that should be matched
      data = "ABCABC" * 10
      encoder.encode_stream(data)

      # Should compress well due to matches
      # 60 bytes of input should compress significantly
      expect(output.string.bytesize).to be < 100
    end

    it "handles long matches" do
      output = StringIO.new
      encoder = described_class.new(output)

      # Long repetitive sequence
      data = "The quick brown fox " * 50
      encoder.encode_stream(data)

      # Should achieve good compression
      expect(output.string.bytesize).to be < data.bytesize / 5
    end
  end

  describe "literal encoding" do
    it "uses matched literal encoding after matches" do
      output = StringIO.new
      encoder = described_class.new(output)

      # Pattern that creates match followed by literal
      # "AB" repeats, then "C" is literal after match
      data = "ABABC"
      encoder.encode_stream(data)

      expect(output.string.bytesize).to be > 13
    end

    it "uses unmatched literal encoding at start" do
      output = StringIO.new
      encoder = described_class.new(output)

      # First few bytes are always unmatched literals
      data = "ABC"
      encoder.encode_stream(data)

      expect(output.string.bytesize).to be > 13
    end
  end

  describe "state machine integration" do
    it "transitions states correctly during encoding" do
      output = StringIO.new
      encoder = described_class.new(output)

      # Mix of literals and matches to exercise state transitions
      data = "AABBAABBCC"
      encoder.encode_stream(data)

      # Should complete without errors
      expect(output.string.bytesize).to be > 13
    end
  end

  describe "EOS marker" do
    it "encodes EOS marker at end of stream" do
      output = StringIO.new
      encoder = described_class.new(output)

      data = "Test"
      encoder.encode_stream(data)

      # Output should include EOS marker
      # (difficult to verify directly, but should not crash)
      expect(output.string.bytesize).to be > 13
    end
  end

  describe "edge cases" do
    it "handles all-same-byte input" do
      output = StringIO.new
      encoder = described_class.new(output)

      data = "A" * 100
      encoder.encode_stream(data)

      # Should compress extremely well
      expect(output.string.bytesize).to be < 50
    end

    it "handles binary data" do
      output = StringIO.new
      encoder = described_class.new(output)

      data = "\x00\x01\x02\xFF" * 10
      encoder.encode_stream(data)

      expect(output.string.bytesize).to be >= 13
    end

    it "handles data with no matches" do
      output = StringIO.new
      encoder = described_class.new(output)

      # Random-ish data with no repetition
      data = (0..25).to_a.join
      encoder.encode_stream(data)

      # Should still encode successfully
      expect(output.string.bytesize).to be >= 13
    end
  end
end
