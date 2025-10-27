# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::FilterPipeline do
  let(:pipeline) { described_class.new }
  let(:bcj_filter) { Omnizip::Filters::BcjX86.new }

  describe "#initialize" do
    it "creates an empty pipeline" do
      expect(pipeline.empty?).to be true
      expect(pipeline.size).to eq(0)
    end
  end

  describe "#add_filter" do
    it "adds a filter to the pipeline" do
      pipeline.add_filter(bcj_filter)

      expect(pipeline.empty?).to be false
      expect(pipeline.size).to eq(1)
    end

    it "returns self for method chaining" do
      result = pipeline.add_filter(bcj_filter)

      expect(result).to eq(pipeline)
    end

    it "allows adding multiple filters" do
      filter1 = Omnizip::Filters::BcjX86.new
      filter2 = Omnizip::Filters::BcjX86.new

      pipeline.add_filter(filter1).add_filter(filter2)

      expect(pipeline.size).to eq(2)
    end
  end

  describe "#empty?" do
    it "returns true for empty pipeline" do
      expect(pipeline.empty?).to be true
    end

    it "returns false after adding a filter" do
      pipeline.add_filter(bcj_filter)

      expect(pipeline.empty?).to be false
    end
  end

  describe "#size" do
    it "returns 0 for empty pipeline" do
      expect(pipeline.size).to eq(0)
    end

    it "returns correct count after adding filters" do
      pipeline.add_filter(bcj_filter)
      expect(pipeline.size).to eq(1)

      pipeline.add_filter(Omnizip::Filters::BcjX86.new)
      expect(pipeline.size).to eq(2)
    end
  end

  describe "#encode and #decode" do
    context "with empty pipeline" do
      it "returns data unchanged when encoding" do
        data = "test data".b
        result = pipeline.encode(data, 0)

        expect(result).to eq(data)
      end

      it "returns data unchanged when decoding" do
        data = "test data".b
        result = pipeline.decode(data, 0)

        expect(result).to eq(data)
      end
    end

    context "with single filter" do
      before { pipeline.add_filter(bcj_filter) }

      it "applies filter during encoding" do
        data = "\xE8\x00\x00\x00\x00".b
        encoded = pipeline.encode(data, 0)

        expect(encoded).not_to eq(data)
      end

      it "round-trips correctly" do
        data = "\xE8\x00\x00\x00\x00".b
        encoded = pipeline.encode(data, 0)
        decoded = pipeline.decode(encoded, 0)

        expect(decoded).to eq(data)
      end

      it "handles position offset" do
        data = "\xE8\x00\x00\x00\x00".b
        position = 100

        encoded = pipeline.encode(data, position)
        decoded = pipeline.decode(encoded, position)

        expect(decoded).to eq(data)
      end
    end

    context "with multiple filters" do
      before do
        # Add two BCJ filters (demonstrating chaining capability)
        pipeline.add_filter(Omnizip::Filters::BcjX86.new)
        pipeline.add_filter(Omnizip::Filters::BcjX86.new)
      end

      it "applies filters in order during encoding" do
        data = "\xE8\x00\x00\x00\x00".b
        encoded = pipeline.encode(data, 0)

        # Should be different from original
        expect(encoded).not_to eq(data)
      end

      it "applies filters in reverse order during decoding" do
        data = "\xE8\x00\x00\x00\x00".b
        encoded = pipeline.encode(data, 0)
        decoded = pipeline.decode(encoded, 0)

        # Should round-trip correctly
        expect(decoded).to eq(data)
      end

      it "handles complex data correctly" do
        data = "Hello, World! ".b
        data += "\xE8\x00\x00\x00\x00".b
        encoded = pipeline.encode(data, 0)
        decoded = pipeline.decode(encoded, 0)

        expect(decoded).to eq(data)
      end
    end

    context "with large data" do
      before { pipeline.add_filter(bcj_filter) }

      it "handles large buffers efficiently" do
        data = ("\x00" * 10_000).b
        data[1000, 5] = "\xE8\x00\x00\x00\x00".b

        encoded = pipeline.encode(data, 0)
        decoded = pipeline.decode(encoded, 0)

        expect(decoded).to eq(data)
      end
    end
  end

  describe "#clear" do
    it "removes all filters from pipeline" do
      pipeline.add_filter(bcj_filter)
      pipeline.add_filter(Omnizip::Filters::BcjX86.new)

      expect(pipeline.size).to eq(2)

      pipeline.clear

      expect(pipeline.empty?).to be true
      expect(pipeline.size).to eq(0)
    end

    it "allows adding new filters after clear" do
      pipeline.add_filter(bcj_filter)
      pipeline.clear
      pipeline.add_filter(Omnizip::Filters::BcjX86.new)

      expect(pipeline.size).to eq(1)
    end
  end
end
