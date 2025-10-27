# frozen_string_literal: true

require "spec_helper"

RSpec.describe Omnizip::IO::StreamManager do
  describe "#initialize" do
    it "wraps StringIO for string data" do
      manager = described_class.new("test data")

      expect(manager.source).to be_a(StringIO)
    end

    it "wraps IO objects directly" do
      io = StringIO.new("test")
      manager = described_class.new(io)

      expect(manager.source).to eq(io)
    end

    it "raises error for invalid source type" do
      expect do
        described_class.new(123)
      end.to raise_error(ArgumentError, /Invalid source type/)
    end
  end

  describe "#buffered_input" do
    it "creates buffered input from source" do
      manager = described_class.new(StringIO.new("test"))
      input = manager.buffered_input

      expect(input).to be_a(Omnizip::IO::BufferedInput)
    end
  end

  describe "#buffered_output" do
    it "creates buffered output to source" do
      manager = described_class.new(StringIO.new)
      output = manager.buffered_output

      expect(output).to be_a(Omnizip::IO::BufferedOutput)
    end
  end

  describe "#read_all" do
    it "reads all data from source" do
      manager = described_class.new(StringIO.new("test data"))

      expect(manager.read_all).to eq("test data")
    end
  end

  describe "#write" do
    it "writes data to source" do
      io = StringIO.new
      manager = described_class.new(io)
      manager.write("test")

      expect(io.string).to eq("test")
    end
  end
end
