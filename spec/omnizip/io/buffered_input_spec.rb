# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::IO::BufferedInput do
  let(:data) { "Hello, World!" * 1000 }
  let(:source) { StringIO.new(data) }

  describe "#initialize" do
    it "creates buffered input with default buffer size" do
      input = described_class.new(source)

      expect(input.buffer_size).to eq(described_class::DEFAULT_BUFFER_SIZE)
    end

    it "creates buffered input with custom buffer size" do
      input = described_class.new(source, buffer_size: 1024)

      expect(input.buffer_size).to eq(1024)
    end
  end

  describe "#read" do
    it "reads requested number of bytes" do
      input = described_class.new(source, buffer_size: 100)
      result = input.read(50)

      expect(result.bytesize).to eq(50)
      expect(result).to eq(data[0, 50])
    end

    it "returns nil at EOF" do
      input = described_class.new(StringIO.new("test"))
      input.read(10)

      expect(input.read(10)).to be_nil
    end

    it "handles reads larger than buffer" do
      input = described_class.new(source, buffer_size: 100)
      result = input.read(500)

      expect(result.bytesize).to eq(500)
      expect(result).to eq(data[0, 500])
    end
  end

  describe "#read_byte" do
    it "reads single byte" do
      input = described_class.new(source)
      byte = input.read_byte

      expect(byte).to eq(data.getbyte(0))
    end

    it "returns nil at EOF" do
      input = described_class.new(StringIO.new("H"))
      input.read_byte

      expect(input.read_byte).to be_nil
    end
  end

  describe "#eof?" do
    it "returns false when data available" do
      input = described_class.new(source)

      expect(input.eof?).to be false
    end

    it "returns true at end of file" do
      input = described_class.new(StringIO.new("test"))
      input.read(10)

      expect(input.eof?).to be true
    end
  end
end
