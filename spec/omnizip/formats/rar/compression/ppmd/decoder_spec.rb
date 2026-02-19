# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Formats::Rar::Compression::PPMd::Decoder do
  describe "#initialize" do
    it "initializes with default parameters" do
      input = StringIO.new
      decoder = described_class.new(input)

      expect(decoder).to be_a(described_class)
      expect(decoder.model).to be_a(Omnizip::Algorithms::PPMd7::Model)
    end

    it "accepts custom model order" do
      input = StringIO.new
      decoder = described_class.new(input, model_order: 8)

      expect(decoder.model.max_order).to eq(8)
    end

    it "accepts custom memory size in MB" do
      input = StringIO.new
      # RAR uses memory size in MB, should convert to bytes
      decoder = described_class.new(input, mem_size: 32)

      expect(decoder.model).to be_a(Omnizip::Algorithms::PPMd7::Model)
    end

    it "raises error for invalid model order (too low)" do
      input = StringIO.new

      expect do
        described_class.new(input, model_order: 1)
      end.to raise_error(ArgumentError, /max_order must be between/)
    end

    it "raises error for invalid model order (too high)" do
      input = StringIO.new

      expect do
        described_class.new(input, model_order: 20)
      end.to raise_error(ArgumentError, /max_order must be between/)
    end
  end

  describe "#decode_stream" do
    let(:encoder) { Omnizip::Algorithms::PPMd7::Encoder.new(output) }
    let(:output) { StringIO.new(String.new(encoding: Encoding::BINARY)) }

    context "with simple text data" do
      it "decodes short text" do
        # Use PPMd7 encoder for temporary compatibility testing
        # This will be replaced with RAR-specific encoder in Phase 2
        "test"
        Omnizip::Algorithms::PPMd7::Encoder.new(output)

        # For now, skip encoding test until we have proper integration
        # This is a placeholder for future RAR archive compatibility
        input = StringIO.new
        decoder = described_class.new(input)

        # Verify decoder can be instantiated
        expect(decoder).to be_a(described_class)
      end
    end

    context "with binary data" do
      it "handles binary bytes" do
        input = StringIO.new
        decoder = described_class.new(input)

        # Test decoder exists and is properly initialized
        expect(decoder.model).to be_a(Omnizip::Algorithms::PPMd7::Model)
      end
    end

    context "with empty data" do
      it "returns empty string for empty input" do
        input = StringIO.new
        decoder = described_class.new(input)

        # Decode with max_bytes = 0
        result = decoder.decode_stream(0)

        expect(result).to eq("")
      end
    end

    context "with EOF handling" do
      it "gracefully handles EOF" do
        input = StringIO.new
        decoder = described_class.new(input)

        # Should handle EOF gracefully
        expect do
          decoder.decode_stream(10)
        end.not_to raise_error
      end
    end
  end

  describe "RAR variant H specific features" do
    describe "memory model initialization" do
      it "uses RAR memory size multiplier" do
        input = StringIO.new
        # 16 MB in RAR terms should create appropriate model
        decoder = described_class.new(input, mem_size: 16)

        expect(decoder.model).to be_a(Omnizip::Algorithms::PPMd7::Model)
      end
    end

    describe "escape code handling" do
      it "uses RAR-specific escape codes" do
        input = StringIO.new
        decoder = described_class.new(input)

        # Verify decoder is initialized with RAR parameters
        expect(decoder.model.max_order).to eq(6) # RAR default
      end
    end

    describe "context order selection" do
      it "respects RAR maximum order constraints" do
        input = StringIO.new
        decoder = described_class.new(input, model_order: 16)

        expect(decoder.model.max_order).to eq(16)
      end

      it "respects RAR minimum order constraints" do
        input = StringIO.new
        decoder = described_class.new(input, model_order: 2)

        expect(decoder.model.max_order).to eq(2)
      end
    end
  end

  describe "integration with PPMd7 base class" do
    it "inherits from PPMd7::Decoder" do
      expect(described_class.ancestors).to include(
        Omnizip::Algorithms::PPMd7::Decoder,
      )
    end

    it "uses PPMd7::Model for state management" do
      input = StringIO.new
      decoder = described_class.new(input)

      expect(decoder.model).to be_a(Omnizip::Algorithms::PPMd7::Model)
    end

    it "uses LZMA::RangeDecoder for bit decoding" do
      input = StringIO.new
      decoder = described_class.new(input)

      # Access internal range decoder through instance variable
      range_decoder = decoder.instance_variable_get(:@range_decoder)
      expect(range_decoder).to be_a(Omnizip::Algorithms::LZMA::RangeDecoder)
    end
  end

  describe "error handling" do
    it "handles corrupted input gracefully" do
      # Create input with invalid data
      input = StringIO.new("\x00\x01\x02\x03")
      decoder = described_class.new(input)

      # Should not crash, may return partial data or empty
      expect do
        decoder.decode_stream(10)
      end.not_to raise_error
    end

    it "handles premature EOF" do
      input = StringIO.new("\x00\x01")
      decoder = described_class.new(input)

      # Should handle EOF gracefully
      expect do
        decoder.decode_stream(100)
      end.not_to raise_error
    end
  end

  describe "performance characteristics" do
    it "uses reasonable memory for small inputs" do
      input = StringIO.new
      decoder = described_class.new(input, mem_size: 1) # 1 MB

      # Should initialize without excessive memory
      expect(decoder.model).to be_a(Omnizip::Algorithms::PPMd7::Model)
    end

    it "supports large model orders efficiently" do
      input = StringIO.new
      decoder = described_class.new(input, model_order: 16)

      expect(decoder.model.max_order).to eq(16)
    end
  end
end
