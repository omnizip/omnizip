# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::IO::BufferedOutput do
  let(:destination) { StringIO.new }

  describe "#initialize" do
    it "creates buffered output with default buffer size" do
      output = described_class.new(destination)

      expect(output.buffer_size).to eq(described_class::DEFAULT_BUFFER_SIZE)
    end

    it "creates buffered output with custom buffer size" do
      output = described_class.new(destination, buffer_size: 1024)

      expect(output.buffer_size).to eq(1024)
    end
  end

  describe "#write" do
    it "writes data to buffer" do
      output = described_class.new(destination, buffer_size: 100)
      output.write("test")

      expect(output.position).to eq(4)
    end

    it "flushes when buffer is full" do
      output = described_class.new(destination, buffer_size: 10)
      output.write("Hello, World!")

      expect(destination.string).not_to be_empty
    end

    it "returns number of bytes written" do
      output = described_class.new(destination)
      bytes = output.write("test")

      expect(bytes).to eq(4)
    end
  end

  describe "#write_byte" do
    it "writes single byte" do
      output = described_class.new(destination)
      output.write_byte(65)
      output.flush

      expect(destination.string).to eq("A")
    end
  end

  describe "#flush" do
    it "writes buffered data to destination" do
      output = described_class.new(destination, buffer_size: 100)
      output.write("test data")
      output.flush

      expect(destination.string).to eq("test data")
    end
  end

  describe "#close" do
    it "flushes and closes destination" do
      output = described_class.new(destination)
      output.write("test")
      output.close

      expect(destination.string).to eq("test")
    end
  end
end
