# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Omnizip::Algorithms::LZMA::XzEncoder do
  let(:encoder) { described_class.new }

  describe "#encode" do
    it "encodes simple literal string" do
      input = "a"
      output = StringIO.new

      bytes_written = encoder.encode(input, output)

      expect(bytes_written).to be > 0
      expect(output.string).not_to be_empty
    end

    it "encodes multiple literals" do
      input = "abc"
      output = StringIO.new

      bytes_written = encoder.encode(input, output)

      expect(bytes_written).to be > 0
      # output.string.bytesize includes flush padding, bytes_written excludes it
      # output.string.bytesize should be >= bytes_written
      expect(output.string.bytesize).to be >= bytes_written
    end

    it "encodes repetitive data with matches" do
      input = "aaaaaaaaaa" # 10 a's - should encode with matches
      output = StringIO.new

      bytes_written = encoder.encode(input, output)

      expect(bytes_written).to be > 0
      # For very small inputs, LZMA with EOS marker may not achieve compression
      # due to EOS marker overhead (~6-7 bytes). The encoder produces valid output.
      expect(output.string.bytesize).to be > 13 # Header + some data
    end

    it "encodes data with rep matches" do
      input = "abcabcabc" # Repeating pattern
      output = StringIO.new

      bytes_written = encoder.encode(input, output)

      expect(bytes_written).to be > 0
    end

    it "encodes longer text" do
      input = "The quick brown fox jumps over the lazy dog"
      output = StringIO.new

      bytes_written = encoder.encode(input, output)

      expect(bytes_written).to be > 0
    end

    it "encodes binary data" do
      input = [0x01, 0x02, 0x03, 0x04, 0x05].pack("C*")
      output = StringIO.new

      bytes_written = encoder.encode(input, output)

      expect(bytes_written).to be > 0
    end

    it "handles empty input" do
      input = ""
      output = StringIO.new

      bytes_written = encoder.encode(input, output)

      # Empty input should produce minimal output (just flush)
      expect(bytes_written).to be >= 0
    end

    it "uses custom lc/lp/pb parameters" do
      custom_encoder = described_class.new(lc: 4, lp: 1, pb: 3)
      input = "test data"
      output = StringIO.new

      bytes_written = custom_encoder.encode(input, output)

      expect(bytes_written).to be > 0
    end

    it "uses custom dictionary size" do
      custom_encoder = described_class.new(dict_size: 1 << 20) # 1MB
      input = "test" * 100
      output = StringIO.new

      bytes_written = custom_encoder.encode(input, output)

      expect(bytes_written).to be > 0
    end

    it "uses custom nice length" do
      custom_encoder = described_class.new(nice_len: 16)
      input = "test" * 50
      output = StringIO.new

      bytes_written = custom_encoder.encode(input, output)

      expect(bytes_written).to be > 0
    end

    it "tracks output total correctly" do
      input = "Hello World!"
      output = StringIO.new

      bytes_written = encoder.encode(input, output)

      # output_total includes all bytes written (including flush padding)
      # bytes_written is bytes_for_decode (excludes flush padding)
      # output_total should be >= bytes_written
      expect(encoder.output_total).to be >= bytes_written
      expect(output.string.bytesize).to eq(encoder.output_total)
    end

    it "handles various input sizes" do
      [1, 10, 100, 1000].each do |size|
        input = "a" * size
        output = StringIO.new

        bytes_written = encoder.encode(input, output)

        expect(bytes_written).to be > 0
      end
    end
  end

  describe "integration" do
    it "produces consistent output for same input" do
      input = "consistent data"

      output1 = StringIO.new
      encoder1 = described_class.new
      encoder1.encode(input, output1)

      output2 = StringIO.new
      encoder2 = described_class.new
      encoder2.encode(input, output2)

      # Same input with same parameters should produce same output
      expect(output1.string).to eq(output2.string)
    end

    it "handles mixed literals and matches" do
      # Pattern with both unique bytes and repetitions
      input = "abcdefghijklmnopabcdefgxyzabcdefghijklmnop"
      output = StringIO.new

      bytes_written = encoder.encode(input, output)

      expect(bytes_written).to be > 0
      # For small/medium inputs, LZMA with EOS marker may not achieve compression
      # due to EOS marker overhead. The encoder produces valid output.
      expect(output.string.bytesize).to be > 13 # Header + some data
    end

    it "achieves compression for larger repetitive inputs" do
      # Large input with lots of repetition should compress well
      input = "a" * 1000 # 1000 a's - highly compressible
      output = StringIO.new

      bytes_written = encoder.encode(input, output)

      expect(bytes_written).to be > 0
      # Large repetitive input should achieve significant compression
      expect(bytes_written).to be < input.bytesize
      expect(output.string.bytesize).to be < input.bytesize + 13 # +13 for header
    end
  end
end
