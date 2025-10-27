# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::Filters::Delta do
  describe "#initialize" do
    it "creates filter with default distance" do
      filter = described_class.new
      expect(filter.distance).to eq(1)
    end

    it "creates filter with specified distance" do
      filter = described_class.new(3)
      expect(filter.distance).to eq(3)
    end

    it "raises error for non-integer distance" do
      expect { described_class.new("3") }.to raise_error(ArgumentError,
                                                         /must be an integer/)
    end

    it "raises error for distance less than 1" do
      expect { described_class.new(0) }.to raise_error(ArgumentError,
                                                       /must be at least 1/)
    end

    it "raises error for distance greater than 256" do
      expect { described_class.new(257) }.to raise_error(ArgumentError,
                                                         /must not exceed 256/)
    end
  end

  describe ".metadata" do
    it "returns filter metadata" do
      metadata = described_class.metadata
      expect(metadata[:name]).to eq("Delta")
      expect(metadata[:description]).to include("multimedia")
    end
  end

  describe "round-trip with distance=1 (audio)" do
    let(:filter) { described_class.new(1) }

    it "handles empty data" do
      data = ""
      encoded = filter.encode(data)
      decoded = filter.decode(encoded)
      expect(decoded).to eq(data)
    end

    it "handles single byte" do
      data = "\x42"
      encoded = filter.encode(data)
      decoded = filter.decode(encoded)
      expect(decoded).to eq(data)
    end

    it "handles gradual increase (audio-like)" do
      data = (0..255).to_a.pack("C*")
      encoded = filter.encode(data)
      decoded = filter.decode(encoded)
      expect(decoded).to eq(data)
    end

    it "reduces byte range for gradual data" do
      data = (0..255).to_a.pack("C*")
      encoded = filter.encode(data)
      # First byte unchanged, rest should be 1 (difference)
      expect(encoded.getbyte(0)).to eq(0)
      (1..255).each do |i|
        expect(encoded.getbyte(i)).to eq(1)
      end
    end

    it "handles wrap-around arithmetic" do
      data = [255, 0, 1].pack("C*")
      encoded = filter.encode(data)
      # 255 unchanged, 0-255=1 (mod 256), 1-0=1
      expect(encoded.getbyte(0)).to eq(255)
      expect(encoded.getbyte(1)).to eq(1)
      expect(encoded.getbyte(2)).to eq(1)

      decoded = filter.decode(encoded)
      expect(decoded).to eq(data)
    end

    it "handles random data" do
      data = Array.new(1000) { rand(256) }.pack("C*")
      encoded = filter.encode(data)
      decoded = filter.decode(encoded)
      expect(decoded).to eq(data)
    end
  end

  describe "round-trip with distance=2 (stereo 16-bit)" do
    let(:filter) { described_class.new(2) }

    it "handles data with repeating pattern" do
      data = [10, 20, 12, 22, 14, 24].pack("C*")
      encoded = filter.encode(data)
      decoded = filter.decode(encoded)
      expect(decoded).to eq(data)
    end

    it "leaves first two bytes unchanged" do
      data = [100, 200, 150, 250].pack("C*")
      encoded = filter.encode(data)
      expect(encoded.getbyte(0)).to eq(100)
      expect(encoded.getbyte(1)).to eq(200)
    end

    it "handles large buffer" do
      data = Array.new(10_000) { rand(256) }.pack("C*")
      encoded = filter.encode(data)
      decoded = filter.decode(encoded)
      expect(decoded).to eq(data)
    end
  end

  describe "round-trip with distance=3 (RGB)" do
    let(:filter) { described_class.new(3) }

    it "handles RGB pixel data" do
      # Simulate RGB pixels: (128,130,132), (128,130,132), ...
      data = ([128, 130, 132] * 100).pack("C*")
      encoded = filter.encode(data)
      decoded = filter.decode(encoded)
      expect(decoded).to eq(data)
    end

    it "compresses well for repeated RGB values" do
      # Identical RGB pixels
      data = ([128, 130, 132] * 100).pack("C*")
      encoded = filter.encode(data)
      # After first pixel, each channel should have diff=0
      (3..299).step(3) do |i|
        expect(encoded.getbyte(i)).to eq(0)
        expect(encoded.getbyte(i + 1)).to eq(0)
        expect(encoded.getbyte(i + 2)).to eq(0)
      end
    end

    it "leaves first three bytes unchanged" do
      data = [10, 20, 30, 40, 50, 60].pack("C*")
      encoded = filter.encode(data)
      expect(encoded.getbyte(0)).to eq(10)
      expect(encoded.getbyte(1)).to eq(20)
      expect(encoded.getbyte(2)).to eq(30)
    end
  end

  describe "round-trip with distance=4 (RGBA or 32-bit)" do
    let(:filter) { described_class.new(4) }

    it "handles RGBA pixel data" do
      # Simulate RGBA pixels: (128,130,132,255), repeated
      data = ([128, 130, 132, 255] * 100).pack("C*")
      encoded = filter.encode(data)
      decoded = filter.decode(encoded)
      expect(decoded).to eq(data)
    end

    it "handles 32-bit integer sequences" do
      # Little-endian 32-bit integers
      data = [0x12345678, 0x12345679, 0x1234567A].pack("V*")
      encoded = filter.encode(data)
      decoded = filter.decode(encoded)
      expect(decoded).to eq(data)
    end

    it "leaves first four bytes unchanged" do
      data = [10, 20, 30, 40, 50, 60, 70, 80].pack("C*")
      encoded = filter.encode(data)
      expect(encoded.getbyte(0)).to eq(10)
      expect(encoded.getbyte(1)).to eq(20)
      expect(encoded.getbyte(2)).to eq(30)
      expect(encoded.getbyte(3)).to eq(40)
    end
  end

  describe "position parameter" do
    let(:filter) { described_class.new(1) }

    it "ignores position in encode" do
      data = [10, 20, 30].pack("C*")
      encoded1 = filter.encode(data, 0)
      encoded2 = filter.encode(data, 1000)
      expect(encoded1).to eq(encoded2)
    end

    it "ignores position in decode" do
      data = [10, 20, 30].pack("C*")
      encoded = filter.encode(data, 0)
      decoded1 = filter.decode(encoded, 0)
      decoded2 = filter.decode(encoded, 1000)
      expect(decoded1).to eq(decoded2)
      expect(decoded1).to eq(data)
    end
  end

  describe "edge cases" do
    let(:filter) { described_class.new(1) }

    it "handles data shorter than distance" do
      filter = described_class.new(5)
      data = [1, 2, 3].pack("C*")
      encoded = filter.encode(data)
      # All bytes unchanged when shorter than distance
      expect(encoded).to eq(data)
      decoded = filter.decode(encoded)
      expect(decoded).to eq(data)
    end

    it "handles binary zeros" do
      data = "\x00" * 100
      encoded = filter.encode(data)
      decoded = filter.decode(encoded)
      expect(decoded).to eq(data)
    end

    it "handles binary 0xFF" do
      data = ("\xFF" * 100).b
      encoded = filter.encode(data)
      decoded = filter.decode(encoded)
      expect(decoded).to eq(data)
    end

    it "handles mixed binary data" do
      data = [0, 255, 128, 64, 192, 32].pack("C*")
      encoded = filter.encode(data)
      decoded = filter.decode(encoded)
      expect(decoded).to eq(data)
    end
  end

  describe "registry integration" do
    it "is registered as :delta" do
      expect(Omnizip::FilterRegistry.registered?(:delta)).to be true
    end

    it "can be retrieved from registry" do
      klass = Omnizip::FilterRegistry.get(:delta)
      expect(klass).to eq(described_class)
    end

    it "creates instance from registry" do
      klass = Omnizip::FilterRegistry.get(:delta)
      filter = klass.new(2)
      expect(filter).to be_a(described_class)
      expect(filter.distance).to eq(2)
    end
  end
end
