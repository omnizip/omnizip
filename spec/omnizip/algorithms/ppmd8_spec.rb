# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Algorithms::PPMd8 do
  let(:algorithm) { described_class.new }

  describe ".metadata" do
    it "returns correct algorithm metadata" do
      metadata = described_class.metadata

      expect(metadata.name).to eq("ppmd8")
      expect(metadata.description).to include("PPMd8")
      expect(metadata.supports_streaming).to be true
    end
  end

  describe "#compress and #decompress" do
    let(:input_data) { "Hello, PPMd8 compression test!" }

    it "raises NotImplementedError when compressing" do
      compressed = StringIO.new(String.new(encoding: Encoding::BINARY))

      expect do
        algorithm.compress(StringIO.new(input_data), compressed)
      end.to raise_error(NotImplementedError,
                         /PPMd8 compression is not yet fully implemented/)
    end

    it "raises NotImplementedError when decompressing" do
      compressed = StringIO.new(String.new(encoding: Encoding::BINARY))
      decompressed = StringIO.new(String.new(encoding: Encoding::BINARY))

      expect do
        algorithm.decompress(compressed, decompressed)
      end.to raise_error(NotImplementedError,
                         /PPMd8 decompression is not yet fully implemented/)
    end

    it "raises NotImplementedError with custom model order" do
      compressed = StringIO.new(String.new(encoding: Encoding::BINARY))

      expect do
        algorithm.compress(
          StringIO.new(input_data),
          compressed,
          model_order: 8,
        )
      end.to raise_error(NotImplementedError,
                         /PPMd8 compression is not yet fully implemented/)
    end

    it "raises NotImplementedError with custom memory size" do
      compressed = StringIO.new(String.new(encoding: Encoding::BINARY))

      expect do
        algorithm.compress(
          StringIO.new(input_data),
          compressed,
          mem_size: 1 << 22,
        )
      end.to raise_error(NotImplementedError,
                         /PPMd8 compression is not yet fully implemented/)
    end

    it "raises NotImplementedError with RESTART restoration method" do
      compressed = StringIO.new(String.new(encoding: Encoding::BINARY))

      expect do
        algorithm.compress(
          StringIO.new(input_data),
          compressed,
          restore_method: 0,
        )
      end.to raise_error(NotImplementedError,
                         /PPMd8 compression is not yet fully implemented/)
    end

    it "raises NotImplementedError with CUT_OFF restoration method" do
      compressed = StringIO.new(String.new(encoding: Encoding::BINARY))

      expect do
        algorithm.compress(
          StringIO.new(input_data),
          compressed,
          restore_method: 1,
        )
      end.to raise_error(NotImplementedError,
                         /PPMd8 compression is not yet fully implemented/)
    end
  end

  describe "restoration methods" do
    it "handles RESTART restoration" do
      model = Omnizip::Algorithms::PPMd8::Model.new(6, 1 << 20, 0)
      expect(model.restoration_method).to be_a(
        Omnizip::Algorithms::PPMd8::RestorationMethod,
      )
    end

    it "handles CUT_OFF restoration" do
      model = Omnizip::Algorithms::PPMd8::Model.new(6, 1 << 20, 1)
      expect(model.restoration_method).to be_a(
        Omnizip::Algorithms::PPMd8::RestorationMethod,
      )
    end
  end
end
